#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the guarded current-kernel ext4 and dm-crypt+ext4 scratch appliance.
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
build_root=${BUILD_ROOT:-$repo_root/build}
baseline_source=${KERNEL_SOURCE:-$build_root/linux-v7.1.3}
diagnostic_source=$build_root/linux-v7.1.3-msi-diagnostic
patch_file=$repo_root/patches/0001-ahci-mbp11-3-opt-in-msi-diagnostic.patch
tool_root=$build_root/filesystem-stack-tools
probe_source=$repo_root/tools/filesystem-sync-probe.c
probe_binary=$tool_root/filesystem-sync-probe
expected_commit=199c9959d3a9b53f346c221757fc7ac507fbac50
profile=${PROFILE:-legacy-stack}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[[ -d $baseline_source/.git ]] || die "authenticated Linux source not found: $baseline_source"
[[ $(git -C "$baseline_source" rev-parse HEAD) == "$expected_commit" ]] || \
	die "baseline source is not at authenticated Linux 7.1.3 commit"

case "$profile" in
	legacy-stack)
		kernel_source=$baseline_source
		work_root=${WORK_ROOT:-$build_root/filesystem-stack-legacy-v7.1.3}
		localversion=-mbp-ahci-legacy-stack
		kernel_cmdline='rdinit=/init console=tty0 loglevel=7 printk.time=1 nomodeset panic=30 mbp_ahci.write_test=1 mbp_ahci.stack_test=1'
		expected_kernel_diff=
		[[ -z $(git -C "$kernel_source" status --porcelain --untracked-files=no) ]] || \
			die "authenticated baseline source contains tracked modifications"
		;;
	msi-stack)
		[[ -z ${KERNEL_SOURCE:-} ]] || \
			die "KERNEL_SOURCE override is supported only by the legacy-stack profile"
		[[ -f $patch_file ]] || die "reviewed MSI diagnostic patch not found: $patch_file"
		if [[ ! -e $diagnostic_source/.git ]]; then
			git -C "$baseline_source" worktree add --detach \
				"$diagnostic_source" "$expected_commit"
		fi
		[[ $(git -C "$diagnostic_source" rev-parse HEAD) == "$expected_commit" ]] || \
			die "MSI diagnostic source is not at the authenticated Linux 7.1.3 commit"
		if git -C "$diagnostic_source" diff --quiet -- drivers/ata/ahci.c; then
			git -C "$diagnostic_source" apply "$patch_file"
		fi
		cmp -s "$patch_file" \
			<(git -C "$diagnostic_source" diff --no-ext-diff --binary -- drivers/ata/ahci.c) || \
			die "MSI diagnostic source does not exactly match the reviewed patch"
		[[ -z $(git -C "$diagnostic_source" status --porcelain --untracked-files=normal | \
			grep -v '^ M drivers/ata/ahci.c$') ]] || \
			die "MSI diagnostic source contains changes outside the reviewed AHCI patch"
		kernel_source=$diagnostic_source
		work_root=$repo_root/build/filesystem-stack-msi-v7.1.3
		localversion=-mbp-ahci-msi-stack
		kernel_cmdline='rdinit=/init console=tty0 loglevel=7 printk.time=1 nomodeset panic=30 mbp_ahci.write_test=1 mbp_ahci.stack_test=1 ahci.mbp11_3_msi_diagnostic=1'
		expected_kernel_diff=$patch_file
		;;
	msi-noncq-stack)
		[[ -z ${KERNEL_SOURCE:-} ]] || \
			die "KERNEL_SOURCE override is supported only by the legacy-stack profile"
		[[ -f $patch_file ]] || die "reviewed MSI diagnostic patch not found: $patch_file"
		if [[ ! -e $diagnostic_source/.git ]]; then
			git -C "$baseline_source" worktree add --detach \
				"$diagnostic_source" "$expected_commit"
		fi
		[[ $(git -C "$diagnostic_source" rev-parse HEAD) == "$expected_commit" ]] || \
			die "MSI diagnostic source is not at the authenticated Linux 7.1.3 commit"
		if git -C "$diagnostic_source" diff --quiet -- drivers/ata/ahci.c; then
			git -C "$diagnostic_source" apply "$patch_file"
		fi
		cmp -s "$patch_file" \
			<(git -C "$diagnostic_source" diff --no-ext-diff --binary -- drivers/ata/ahci.c) || \
			die "MSI diagnostic source does not exactly match the reviewed patch"
		[[ -z $(git -C "$diagnostic_source" status --porcelain --untracked-files=normal | \
			grep -v '^ M drivers/ata/ahci.c$') ]] || \
			die "MSI diagnostic source contains changes outside the reviewed AHCI patch"
		kernel_source=$diagnostic_source
		work_root=$repo_root/build/filesystem-stack-msi-noncq-v7.1.3
		localversion=-mbp-ahci-msi-noncq-stack
		kernel_cmdline='rdinit=/init console=tty0 loglevel=7 printk.time=1 nomodeset panic=30 mbp_ahci.write_test=1 mbp_ahci.stack_test=1 ahci.mbp11_3_msi_diagnostic=1 libata.force=noncq'
		expected_kernel_diff=$patch_file
		;;
	*)
		die "unsupported PROFILE '$profile' (expected legacy-stack, msi-stack, or msi-noncq-stack)"
		;;
esac

[[ -f $probe_source ]] || die "filesystem sync probe source not found: $probe_source"

for command in gcc strip file mkfs.ext4 e2fsck dmsetup; do
	command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

install -d -m 0755 "$tool_root"
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
	die 'filesystem sync probe is not statically linked'

KERNEL_SOURCE=$kernel_source \
BUILD_ROOT=$build_root \
WORK_ROOT=$work_root \
KERNEL_LOCALVERSION=$localversion \
EXPECTED_KERNEL_RELEASE="7.1.3$localversion" \
KERNEL_CMDLINE=$kernel_cmdline \
EXPECTED_KERNEL_DIFF=$expected_kernel_diff \
INIT_SCRIPT=$repo_root/scripts/initramfs/write-ab-init \
INITRAMFS_STATIC_BINARIES=$probe_binary \
INITRAMFS_DYNAMIC_BINARIES="$(command -v mkfs.ext4) $(command -v e2fsck) $(command -v dmsetup)" \
ENABLE_FILESYSTEM_STACK=1 \
CLEAN=${CLEAN:-1} \
JOBS=${JOBS:-$(nproc)} \
	"$repo_root/scripts/build-readonly-baseline.sh"

printf 'Profile: %s\n' "$profile"
printf 'Artifact root: %s\n' "$work_root/artifact"
printf 'Probe SHA-256: %s\n' "$(sha256sum "$probe_binary" | cut -d' ' -f1)"
