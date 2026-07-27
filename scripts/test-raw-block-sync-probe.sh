#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Destructive QA for the raw probe, confined to a newly created loop image.
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
qa_root=${QA_ROOT:-$repo_root/build/write-ab-probe-qa}
image=$qa_root/synthetic-ssd.img
probe=$qa_root/raw-block-sync-probe
loop=

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

cleanup() {
	local rc=$?
	trap - EXIT INT TERM
	if [[ -n $loop ]]; then
		sudo losetup -d "$loop" 2>/dev/null || true
	fi
	exit "$rc"
}
trap cleanup EXIT INT TERM

for command in gcc file truncate sudo losetup sgdisk partprobe udevadm \
	mkfs.exfat fsck.exfat dd cmp rg sha256sum; do
	command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

rm -rf -- "$qa_root"
install -d -m 0755 "$qa_root"
gcc \
	-std=c11 \
	-O2 \
	-static \
	-Wall \
	-Wextra \
	-Werror \
	-Wformat=2 \
	-Wshadow \
	-fstack-protector-strong \
	-Wl,--build-id=none \
	-o "$probe" \
	"$repo_root/tools/raw-block-sync-probe.c"
file "$probe" | grep -q 'statically linked' || die 'probe is not statically linked'

truncate -s 6G "$image"
loop=$(sudo losetup --find --show --partscan "$image")
sudo sgdisk \
	--clear \
	--new=1:2048:+5G \
	--typecode=1:0700 \
	--change-name=1:MBPTEST \
	"$loop" >/dev/null
sudo partprobe "$loop"
sudo udevadm settle

partition="${loop}p1"
[[ -b $partition ]] || die "synthetic partition did not appear: $partition"
sudo mkfs.exfat -n MBPTEST "$partition" >/dev/null

if sudo "$probe" "$loop" > "$qa_root/whole-disk-refusal.txt" 2>&1; then
	die 'probe unexpectedly accepted a whole disk'
fi
rg -q 'whole disk|partition attribute' "$qa_root/whole-disk-refusal.txt" || \
	die 'whole-disk refusal did not report the expected guard'

sudo dd if="$partition" of="$qa_root/header-before.bin" bs=1M count=32 status=none
sudo dd if="$loop" of="$qa_root/prefix-before.bin" bs=1M count=1 status=none
sudo "$probe" "$partition" | tee "$qa_root/probe-output.txt"
sudo dd if="$partition" of="$qa_root/header-after.bin" bs=1M count=32 status=none
sudo dd if="$loop" of="$qa_root/prefix-after.bin" bs=1M count=1 status=none

cmp "$qa_root/header-before.bin" "$qa_root/header-after.bin"
cmp "$qa_root/prefix-before.bin" "$qa_root/prefix-after.bin"
rg -q '^result=pass$' "$qa_root/probe-output.txt" || die 'probe did not report success'
sudo fsck.exfat -n "$partition"

printf 'Synthetic destructive-target QA passed.\n'
sha256sum \
	"$qa_root/header-before.bin" \
	"$qa_root/header-after.bin" \
	"$qa_root/prefix-before.bin" \
	"$qa_root/prefix-after.bin"
