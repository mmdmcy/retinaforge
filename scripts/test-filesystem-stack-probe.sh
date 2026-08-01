#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Destructive ext4 and dm-crypt+ext4 QA confined to a synthetic loop image.
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
qa_root=$(realpath -m "${QA_ROOT:-$repo_root/build/filesystem-stack-probe-qa}")
image=$qa_root/synthetic-ssd.img
probe=$qa_root/filesystem-sync-probe
mountpoint=$qa_root/mnt
mapping="mbp_stack_qa_$$"
loop=
mounted=0
mapping_active=0

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

cleanup() {
	local rc=$?
	trap - EXIT INT TERM
	if ((mounted)); then
		sudo umount "$mountpoint" 2>/dev/null || true
	fi
	if ((mapping_active)); then
		sudo dmsetup remove --noudevsync "$mapping" 2>/dev/null || true
	fi
	if [[ -n $loop ]]; then
		sudo blockdev --setrw "$loop" 2>/dev/null || true
		sudo losetup -d "$loop" 2>/dev/null || true
	fi
	exit "$rc"
}
trap cleanup EXIT INT TERM

for command in gcc file truncate sudo losetup sgdisk partprobe udevadm \
	mkfs.ext4 e2fsck dmsetup mount umount blockdev dd cmp grep realpath; do
	command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

case "$qa_root/" in
	"$repo_root/build/"*/) ;;
	*) die "QA_ROOT must remain below $repo_root/build" ;;
esac
[[ $qa_root != "$repo_root/build" ]] || die 'QA_ROOT must not be the build root itself'
rm -rf -- "$qa_root"
install -d -m 0755 "$qa_root" "$mountpoint"

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
	"$repo_root/tools/filesystem-sync-probe.c"
file "$probe" | grep -q 'statically linked' || die 'probe is not statically linked'

if "$probe" /dev/shm invalid-target > "$qa_root/non-ext4-refusal.txt" 2>&1; then
	die 'probe unexpectedly accepted a non-ext4 filesystem'
fi
grep -Eq 'not ext4' "$qa_root/non-ext4-refusal.txt" || \
	die 'non-ext4 refusal did not report the expected reason'

truncate -s 6G "$image"
loop=$(sudo losetup --find --show --partscan "$image")
sudo blockdev --setrw "$loop"
sudo sgdisk \
	--clear \
	--new=1:2048:+5G \
	--typecode=1:8300 \
	--change-name=1:MBPTEST \
	"$loop" >/dev/null
sudo partprobe "$loop"
sudo udevadm settle

partition="${loop}p1"
[[ -b $partition ]] || die "synthetic partition did not appear: $partition"
sudo dd if="$loop" of="$qa_root/gpt-prefix-before.bin" bs=1M count=1 status=none
sudo blockdev --setro "$loop"
sudo blockdev --setrw "$partition"
[[ $(sudo blockdev --getro "$partition") == 1 ]] || \
	die 'scratch partition did not inherit the parent read-only state'
sudo blockdev --setrw "$loop"
sudo blockdev --setrw "$partition"
[[ $(sudo blockdev --getro "$partition") == 0 ]] || \
	die 'synthetic scratch partition did not become writable with its parent'

sudo mkfs.ext4 -F -q -L MBPTEST_PLAIN "$partition"
sudo mount -t ext4 -o rw,noatime,data=ordered "$partition" "$mountpoint"
mounted=1
sudo "$probe" "$mountpoint" plain-ext4 | tee "$qa_root/plain-ext4.txt"
sudo umount "$mountpoint"
mounted=0
sudo e2fsck -fn "$partition" > "$qa_root/plain-ext4-fsck.txt"
grep -Eq '^result=pass$' "$qa_root/plain-ext4.txt" || die 'plain ext4 probe failed'

sustained=$qa_root/sustained-sync-probe
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
	-o "$sustained" \
	"$repo_root/tools/sustained-sync-probe.c"
file "$sustained" | grep -q 'statically linked' || die 'sustained probe is not statically linked'
sudo mkfs.ext4 -F -q -L MBPTEST_SUST "$partition"
sudo mount -t ext4 -o rw,noatime,data=ordered "$partition" "$mountpoint"
mounted=1
sudo "$sustained" "$mountpoint" sustained-darwin-mirror | tee "$qa_root/sustained.txt"
sudo umount "$mountpoint"
mounted=0
sudo e2fsck -fn "$partition" > "$qa_root/sustained-fsck.txt"
grep -Eq '^result=pass$' "$qa_root/sustained.txt" || die 'sustained darwin-mirror probe failed'
grep -Eq '^pattern=darwin-sustained-fullfsync-mirror$' "$qa_root/sustained.txt" || \
	die 'sustained probe did not advertise the Darwin mirror pattern'
grep -Eq '^sample_count=64$' "$qa_root/sustained.txt" || \
	die 'sustained probe sample count is not 64'

installer=$qa_root/installer-sync-probe
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
	-o "$installer" \
	"$repo_root/tools/installer-sync-probe.c"
file "$installer" | grep -q 'statically linked' || die 'installer probe is not statically linked'
sudo mkfs.ext4 -F -q -L MBPTEST_HEAVY "$partition"
sudo mount -t ext4 -o rw,noatime,data=ordered "$partition" "$mountpoint"
mounted=1
sudo "$installer" "$mountpoint" installer-plain-heavy | tee "$qa_root/installer-heavy.txt"
sudo umount "$mountpoint"
mounted=0
sudo e2fsck -fn "$partition" > "$qa_root/installer-heavy-fsck.txt"
grep -Eq '^result=pass$' "$qa_root/installer-heavy.txt" || die 'installer-plain-heavy probe failed'
grep -Eq '^pattern=installer-smallfile-durable$' "$qa_root/installer-heavy.txt" || \
	die 'installer probe did not advertise the expected pattern'
grep -Eq '^file_count=512$' "$qa_root/installer-heavy.txt" || \
	die 'installer probe file count is not 512'

sectors=$(sudo blockdev --getsz "$partition")
key='000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'
key+='202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f'
sudo dmsetup create "$mapping" --noudevsync \
	--table "0 $sectors crypt aes-xts-plain64 $key 0 $partition 0"
mapping_active=1
sudo dmsetup mknodes "$mapping"
mapper="/dev/mapper/$mapping"
[[ -b $mapper ]] || die "device-mapper node did not appear: $mapper"

mapper_probe=$qa_root/mapper-durable-sync-probe
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
	-o "$mapper_probe" \
	"$repo_root/tools/mapper-durable-sync-probe.c"
file "$mapper_probe" | grep -q 'statically linked' || die 'mapper probe is not statically linked'
if sudo "$mapper_probe" "$partition" should-fail > "$qa_root/mapper-refusal.txt" 2>&1; then
	die 'mapper probe unexpectedly accepted a non-mapper partition'
fi
grep -Eq 'not a device-mapper' "$qa_root/mapper-refusal.txt" || \
	die 'mapper refusal did not mention device-mapper'
sudo "$mapper_probe" "$mapper" dmcrypt-raw | tee "$qa_root/dmcrypt-raw.txt"
grep -Eq '^result=pass$' "$qa_root/dmcrypt-raw.txt" || die 'dmcrypt-raw mapper probe failed'
grep -Eq '^pattern=dmcrypt-raw-durable-sync$' "$qa_root/dmcrypt-raw.txt" || \
	die 'mapper probe did not advertise the expected pattern'

sudo mkfs.ext4 -F -q -L MBPTEST_CRYPT "$mapper"
sudo mount -t ext4 -o rw,noatime,data=ordered "$mapper" "$mountpoint"
mounted=1
sudo "$probe" "$mountpoint" dmcrypt-ext4 | tee "$qa_root/dmcrypt-ext4.txt"
sudo umount "$mountpoint"
mounted=0
sudo e2fsck -fn "$mapper" > "$qa_root/dmcrypt-ext4-fsck.txt"
grep -Eq '^result=pass$' "$qa_root/dmcrypt-ext4.txt" || \
	die 'dm-crypt ext4 probe failed'

sudo dmsetup remove --noudevsync "$mapping"
mapping_active=0
sudo dd if="$loop" of="$qa_root/gpt-prefix-after.bin" bs=1M count=1 status=none
cmp "$qa_root/gpt-prefix-before.bin" "$qa_root/gpt-prefix-after.bin"

printf 'Synthetic ext4 and dm-crypt+ext4 probe QA passed.\n'
printf 'Plain ext4 summary:\n'
grep -E '^(write|fdatasync)_(mean|median|p95|max)_us=|^result=' "$qa_root/plain-ext4.txt"
printf 'Sustained Darwin-mirror summary:\n'
grep -E '^(write|fdatasync)_(mean|median|p95|max)_us=|^long_sync_count=|^first_long_index=|^result=' \
	"$qa_root/sustained.txt"
printf 'Installer-plain-heavy summary:\n'
grep -E '^(fdatasync)_(mean|median|p95|max)_us=|^long_sync_count=|^wall_elapsed_us=|^result=' \
	"$qa_root/installer-heavy.txt"
printf 'dm-crypt raw mapper summary:\n'
grep -E '^(write|fdatasync)_(mean|median|p95|max)_us=|^long_sync_count=|^first_long_index=|^result=' \
	"$qa_root/dmcrypt-raw.txt"
printf 'dm-crypt+ext4 summary:\n'
grep -E '^(write|fdatasync)_(mean|median|p95|max)_us=|^result=' "$qa_root/dmcrypt-ext4.txt"
