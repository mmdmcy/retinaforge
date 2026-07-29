#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build a transient rEFInd probe that exposes the Intel GPU without selecting it.
set -euo pipefail

repo_root=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
refind_root=${REFIND_ROOT:-/usr/share/refind/refind}
artifact_root=${ARTIFACT_ROOT:-$repo_root/build/windows-igpu-probe/artifact}
refind_efi=$refind_root/refind_x64.efi

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[[ -f $refind_efi ]] || \
	die "rEFInd x64 binary not found; set REFIND_ROOT to the extracted refind directory"
command -v objdump >/dev/null || die "objdump is required"
command -v sha256sum >/dev/null || die "sha256sum is required"

artifact_root=$(realpath -m "$artifact_root")
case "$artifact_root/" in
	"$repo_root/build/"*/) ;;
	*) die "ARTIFACT_ROOT must remain below $repo_root/build" ;;
esac

pe_headers=$(objdump -p "$refind_efi")
grep -Fq 'pei-x86-64' < <(objdump -f "$refind_efi") || \
	die "rEFInd binary is not x86-64 PE"
grep -Eiq 'Subsystem[[:space:]]+0000000a|Subsystem[[:space:]]+10[[:space:]]+\(EFI application\)' <<<"$pe_headers" || \
	die "rEFInd binary is not an EFI application"

parent=$(dirname "$artifact_root")
mkdir -p "$parent"
staging=$(mktemp -d "$parent/.artifact.XXXXXX")
cleanup() {
	rm -rf "$staging"
}
trap cleanup EXIT

mkdir -p "$staging/EFI/BOOT"
install -m 0644 "$refind_efi" "$staging/EFI/BOOT/BOOTX64.EFI"

cat >"$staging/EFI/BOOT/refind.conf" <<'EOF'
# RetinaForge transient MacBookPro11,3 Intel-enumeration probe.
# This calls Apple Set OS but does not write gpu-power-prefs or GMUX registers.
timeout 0
textonly true
scanfor internal,manual
spoof_osx_version 10.9
use_nvram false
log_level 0
showtools about,shutdown,reboot
EOF

cat >"$staging/PROBE-README.txt" <<'EOF'
RETINAFORGE WINDOWS INTEL ENUMERATION PROBE

This USB calls Apple's transient Set OS protocol through rEFInd. It does not
select Intel, write gpu-power-prefs, access GMUX, or modify an internal disk.

Boot while holding Option/Alt, select this external EFI Boot, then explicitly
select the existing Windows EFI loader in rEFInd. Do not perform the first boot
unattended. Remove the USB to return to the normal Apple boot path.
EOF

refind_hash=$(sha256sum "$refind_efi" | cut -d' ' -f1)
cat >"$staging/SOURCE.txt" <<EOF
rEFInd input: refind_x64.efi
rEFInd input SHA-256: $refind_hash
Probe behavior: spoof_osx_version 10.9; no timeout; no NVRAM preference writer
RetinaForge target: MacBookPro11,3
EOF

(
	cd "$staging"
	find . -type f ! -name SHA256SUMS -print0 |
		sort -z |
		xargs -0 sha256sum >SHA256SUMS
)

rm -rf "$artifact_root"
mv "$staging" "$artifact_root"
trap - EXIT

(
	cd "$artifact_root"
	sha256sum -c SHA256SUMS
)

printf 'Windows Intel-enumeration probe built: %s\n' "$artifact_root"
printf 'BOOTX64.EFI SHA-256: %s\n' \
	"$(sha256sum "$artifact_root/EFI/BOOT/BOOTX64.EFI" | cut -d' ' -f1)"
