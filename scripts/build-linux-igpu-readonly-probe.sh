#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build a direct-EFI, read-only Linux Intel-enumeration appliance.
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
build_root=${BUILD_ROOT:-$repo_root/build}
artifact_root=${ARTIFACT_ROOT:-$build_root/linux-igpu-readonly-v7.1.3/artifact}
work_root=${WORK_ROOT:-$build_root/linux-igpu-readonly-v7.1.3}
kernel_source=${KERNEL_SOURCE:-$build_root/linux-v7.1.3}
init_script=$repo_root/scripts/initramfs/readonly-baseline-init

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

for command in git install objdump sha256sum find sort xargs; do
	command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[[ -f $init_script ]] || die "Intel probe init script is missing: $init_script"

KERNEL_SOURCE=$kernel_source \
BUILD_ROOT=$build_root \
WORK_ROOT=$work_root \
KERNEL_LOCALVERSION=-mbp-igpu-readonly \
EXPECTED_KERNEL_RELEASE=7.1.3-mbp-igpu-readonly \
KERNEL_CMDLINE='rdinit=/init console=tty0 loglevel=7 printk.time=1 panic=30 mbp_igpu_probe=1' \
INIT_SCRIPT=$init_script \
ENABLE_IGPU_GRAPHICS=1 \
CLEAN=${CLEAN:-1} \
JOBS=${JOBS:-$(nproc)} \
	"$repo_root/scripts/build-readonly-baseline.sh"

[[ -f $artifact_root/lab/vmlinuz ]] || die "probe kernel was not built"
install -m 0644 "$artifact_root/lab/vmlinuz" "$artifact_root/EFI/BOOT/BOOTX64.EFI"

cat >"$artifact_root/PROBE-README.txt" <<'EOF'
RETINAFORGE LINUX INTEL ENUMERATION PROBE

This direct-EFI kernel boots a built-in read-only appliance. It invokes the
upstream Apple Set OS path through the kernel EFI stub, enables i915 and
apple-gmux, and records graphics state to the USB. It does not write internal
storage, gpu-power-prefs, GMUX registers, internal EFI, or boot NVRAM.

Do not use this artifact until its separate USB writer and user-present boot
procedure have been reviewed. A direct Big Sur boot remains the recovery path.
EOF

cat >"$artifact_root/SOURCE.txt" <<EOF
Linux source: v7.1.3 / 199c9959d3a9b53f346c221757fc7ac507fbac50
Boot path: direct EFI stub at EFI/BOOT/BOOTX64.EFI
Target guard: Apple Inc. MacBookPro11,3
Kernel command line: rdinit=/init console=tty0 loglevel=7 printk.time=1 panic=30 mbp_igpu_probe=1
Required graphics: CONFIG_DRM_I915=y CONFIG_APPLE_GMUX=y CONFIG_VGA_SWITCHEROO=y
EOF

(
	cd "$artifact_root"
	find . -type f ! -name SHA256SUMS -print0 |
		sort -z |
		xargs -0 sha256sum >SHA256SUMS
	sha256sum -c SHA256SUMS
)
objdump -f "$artifact_root/EFI/BOOT/BOOTX64.EFI" | \
	grep -Fq 'pei-x86-64' || die "direct EFI kernel is not x86-64 PE"
objdump -x "$artifact_root/EFI/BOOT/BOOTX64.EFI" | \
	grep -q 'Subsystem.*EFI application' || die "direct EFI kernel is not an EFI application"

printf 'Linux Intel-enumeration probe built: %s\n' "$artifact_root"
printf 'Direct EFI kernel SHA-256: %s\n' \
	"$(sha256sum "$artifact_root/EFI/BOOT/BOOTX64.EFI" | cut -d' ' -f1)"
