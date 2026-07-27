#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build one guarded raw write/flush A/B appliance profile.
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
baseline_source=$repo_root/build/linux-v7.1.3
diagnostic_source=$repo_root/build/linux-v7.1.3-msi-diagnostic
patch_file=$repo_root/patches/0001-ahci-mbp11-3-opt-in-msi-diagnostic.patch
probe_source=$repo_root/tools/raw-block-sync-probe.c
probe_root=$repo_root/build/write-ab-tools
probe_binary=$probe_root/raw-block-sync-probe
expected_commit=199c9959d3a9b53f346c221757fc7ac507fbac50
profile=${PROFILE:-}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[[ -n $profile ]] || die 'set PROFILE to legacy-ncq-write or msi-ncq-write'
[[ -d $baseline_source/.git ]] || die "authenticated baseline source not found: $baseline_source"
[[ -f $patch_file ]] || die "reviewed diagnostic patch not found: $patch_file"
[[ -f $probe_source ]] || die "raw block probe source not found: $probe_source"

if [[ ! -e $diagnostic_source/.git ]]; then
	git -C "$baseline_source" worktree add --detach "$diagnostic_source" "$expected_commit"
fi
[[ $(git -C "$diagnostic_source" rev-parse HEAD) == "$expected_commit" ]] || \
	die "diagnostic worktree is not at the authenticated Linux 7.1.3 commit"
if git -C "$diagnostic_source" diff --quiet -- drivers/ata/ahci.c; then
	git -C "$diagnostic_source" apply "$patch_file"
fi
cmp -s "$patch_file" \
	<(git -C "$diagnostic_source" diff --no-ext-diff --binary -- drivers/ata/ahci.c) || \
	die "diagnostic worktree does not exactly match the physically tested MSI patch"

case "$profile" in
	legacy-ncq-write)
		work_root=$repo_root/build/write-ab-legacy-ncq-v7.1.3
		localversion=-mbp-ahci-legacy-ncq-write
		kernel_cmdline='rdinit=/init console=tty0 loglevel=7 printk.time=1 nomodeset panic=30 mbp_ahci.write_test=1'
		;;
	msi-ncq-write)
		work_root=$repo_root/build/write-ab-msi-ncq-v7.1.3
		localversion=-mbp-ahci-msi-ncq-write
		kernel_cmdline='rdinit=/init console=tty0 loglevel=7 printk.time=1 nomodeset panic=30 mbp_ahci.write_test=1 ahci.mbp11_3_msi_diagnostic=1'
		;;
	*)
		die "unsupported PROFILE '$profile' (expected legacy-ncq-write or msi-ncq-write)"
		;;
esac

install -d -m 0755 "$probe_root"
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
	-ffile-prefix-map="$repo_root"=. \
	-fdebug-prefix-map="$repo_root"=. \
	-Wl,--build-id=none \
	-o "$probe_binary" \
	"$probe_source"
strip --strip-all "$probe_binary"
file "$probe_binary" | grep -q 'statically linked' || \
	die 'raw block probe is not statically linked'

KERNEL_SOURCE=$diagnostic_source \
WORK_ROOT=$work_root \
KERNEL_LOCALVERSION=$localversion \
EXPECTED_KERNEL_RELEASE="7.1.3$localversion" \
KERNEL_CMDLINE=$kernel_cmdline \
EXPECTED_KERNEL_DIFF=$patch_file \
INIT_SCRIPT=$repo_root/scripts/initramfs/write-ab-init \
INITRAMFS_STATIC_BINARIES=$probe_binary \
CLEAN=${CLEAN:-1} \
JOBS=${JOBS:-$(nproc)} \
	"$repo_root/scripts/build-readonly-baseline.sh"

printf 'Profile: %s\n' "$profile"
printf 'Artifact root: %s\n' "$work_root/artifact"
printf 'Probe SHA-256: %s\n' "$(sha256sum "$probe_binary" | cut -d' ' -f1)"
