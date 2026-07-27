#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build an opt-in, read-only MSI diagnostic appliance for MacBookPro11,3.
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
baseline_source=$repo_root/build/linux-v7.1.3
diagnostic_source=$repo_root/build/linux-v7.1.3-msi-diagnostic
patch_file=$repo_root/patches/0001-ahci-mbp11-3-opt-in-msi-diagnostic.patch
expected_commit=199c9959d3a9b53f346c221757fc7ac507fbac50
profile=${PROFILE:-msi-noncq}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[[ -d $baseline_source/.git ]] || die "authenticated baseline source not found: $baseline_source"
[[ -f $patch_file ]] || die "reviewed diagnostic patch not found: $patch_file"

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
	die "diagnostic worktree does not exactly match the reviewed patch"

case "$profile" in
	msi-noncq)
		work_root=$repo_root/build/readonly-msi-noncq-v7.1.3
		localversion=-mbp-ahci-msi-noncq
		kernel_cmdline='rdinit=/init console=tty0 loglevel=7 printk.time=1 nomodeset panic=30 ahci.mbp11_3_msi_diagnostic=1 libata.force=noncq'
		;;
	msi-ncq-read)
		work_root=$repo_root/build/readonly-msi-ncq-read-v7.1.3
		localversion=-mbp-ahci-msi-ncq-read
		kernel_cmdline='rdinit=/init console=tty0 loglevel=7 printk.time=1 nomodeset panic=30 ahci.mbp11_3_msi_diagnostic=1'
		;;
	*)
		die "unsupported PROFILE '$profile' (expected msi-noncq or msi-ncq-read)"
		;;
esac

KERNEL_SOURCE=$diagnostic_source \
WORK_ROOT=$work_root \
KERNEL_LOCALVERSION=$localversion \
EXPECTED_KERNEL_RELEASE="7.1.3$localversion" \
KERNEL_CMDLINE=$kernel_cmdline \
EXPECTED_KERNEL_DIFF=$patch_file \
CLEAN=${CLEAN:-1} \
JOBS=${JOBS:-$(nproc)} \
	"$repo_root/scripts/build-readonly-baseline.sh"
