#!/usr/bin/env bash
# Build an Intel-lid UKI on Debian (systemd-ukify). Requires a kernel whose
# apple-gmux has force_igd, and debian-initramfs-intel.sh already run.
set -euo pipefail

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

if ! command -v ukify >/dev/null 2>&1 && ! command -v /usr/lib/systemd/ukify >/dev/null 2>&1; then
	echo "install systemd-ukify (Debian: apt install systemd-ukify systemd-boot-efi)" >&2
	exit 1
fi
UKIFY="$(command -v ukify || true)"
[[ -n $UKIFY ]] || UKIFY=/usr/lib/systemd/ukify

if ! modinfo apple-gmux 2>/dev/null | grep -q 'parm:[[:space:]]*force_igd'; then
	echo "apple-gmux has no force_igd — refuse to build a lid UKI that cannot switch the mux" >&2
	exit 1
fi

kver="${KVER:-$(uname -r)}"
vmlinuz="/boot/vmlinuz-${kver}"
initrd="/boot/initrd.img-${kver}"
[[ -f $vmlinuz ]] || { echo "missing $vmlinuz" >&2; exit 1; }
[[ -f $initrd ]] || { echo "missing $initrd" >&2; exit 1; }

cmdline_file=/etc/kernel/cmdline
[[ -f $cmdline_file ]] || { echo "run debian-initramfs-intel.sh first (writes $cmdline_file)" >&2; exit 1; }
cmdline="$(tr -d '\n' <"$cmdline_file")"

esp="${ESP:-/boot/efi}"
if [[ ! -d $esp ]]; then
	esp=/efi
fi
outdir="${UKI_OUTDIR:-${esp}/EFI/Linux}"
if [[ ! -d $outdir ]]; then
	echo "ESP Linux dir missing ($outdir). Mount the EFI system partition and retry, or set ESP= / UKI_OUTDIR=" >&2
	exit 1
fi
out="${UKI_PATH:-${outdir}/retinaforge-intel.efi}"

"$UKIFY" build \
	--linux="$vmlinuz" \
	--initrd="$initrd" \
	--cmdline="$cmdline" \
	--output="$out"

echo "UKI written: $out"
echo "Boot that EFI image (systemd-boot extra entry, or GRUB chainloader). Do not boot GRUB 'linux' protocol."
