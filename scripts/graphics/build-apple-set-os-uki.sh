#!/usr/bin/env bash
# build-apple-set-os-uki.sh — rebuild the Intel-probe UKI with nvidia-off policy.
#
# Installs modprobe intercepts, builds a UKI via an alternate mkinitcpio config
# (MODULES=i915 + nvidia-off drop-in), and backs up the previous UKI.
#
# Does NOT modify /etc/mkinitcpio.conf. Review printed kernel/cmdline before reboot.
#
# See docs/graphics/intel-first-repro.md

set -euo pipefail

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
KVER="${KVER:-$(uname -r)}"
KNAME="$(cat "/usr/lib/modules/${KVER}/pkgbase" 2>/dev/null || echo linux)"
UKI_DIR="/boot/EFI/Linux"
UKI_PATH="${UKI_PATH:-${UKI_DIR}/cachyos-apple-set-os.efi}"
MODPROBE_DST="/etc/modprobe.d/retinaforge-nvidia-off.conf"
MKINIT_CFG="${root}/scripts/graphics/mkinitcpio-intel-uki.conf"

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

[[ -e "/usr/lib/modules/${KVER}/vmlinuz" ]] || {
	echo "kernel ${KVER} not installed" >&2
	exit 1
}
[[ -f "$MKINIT_CFG" ]] || {
	echo "missing ${MKINIT_CFG}" >&2
	exit 1
}

prod="$(tr -d '\0' </sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo unknown)"
[[ "$prod" == "MacBookPro11,3" ]] || echo "warning: product_name=${prod}, expected MacBookPro11,3"

if [[ -z "${CMDLINE:-}" ]]; then
	keep=()
	# shellcheck disable=SC2013
	for arg in $(tr -d '\n' </proc/cmdline); do
		case "$arg" in
		quiet | splash | BOOT_IMAGE=*|initrd=*|nvidia* | nouveau.* | rd.driver.blacklist=* | modprobe.blacklist=*)
			;;
		*)
			keep+=("$arg")
			;;
		esac
	done
	CMDLINE="${keep[*]}"
fi
if [[ "$CMDLINE" != *root=* ]]; then
	CMDLINE+=" rw root=UUID=$(findmnt -no UUID /)"
fi
if [[ "$CMDLINE" != *plymouth.enable=0* ]]; then
	CMDLINE+=" plymouth.enable=0 systemd.show_status=true loglevel=7"
fi
if [[ "$CMDLINE" != *apple_gmux.force_igd* ]]; then
	CMDLINE+=" apple_gmux.force_igd=1"
fi
if [[ "$CMDLINE" != *i915.enable_dc=0* ]]; then
	CMDLINE+=" i915.enable_dc=0"
fi

CMDLINE_FILE="$(mktemp)"
trap 'rm -f "$CMDLINE_FILE"' EXIT
printf '%s\n' "$CMDLINE" >"$CMDLINE_FILE"

echo "==> kernel: ${KVER} (${KNAME})"
echo "==> cmdline: ${CMDLINE}"
echo "==> UKI: ${UKI_PATH}"

install -Dm644 "${root}/scripts/graphics/nvidia-off-modprobe.conf" "$MODPROBE_DST"

if [[ -f "$UKI_PATH" ]]; then
	backup="${UKI_PATH}.bak-$(date +%Y%m%d-%H%M%S)"
	cp -a "$UKI_PATH" "$backup"
	echo "==> backed up existing UKI -> ${backup}"
fi

install -dm755 "$UKI_DIR"
mkinitcpio --config "$MKINIT_CFG" --kernel "$KVER" --uki "$UKI_PATH" --cmdline "$CMDLINE_FILE"
file "$UKI_PATH" | grep -q 'PE32+' || {
	echo "UKI build did not produce a PE32+ EFI binary" >&2
	exit 1
}

if [[ -f /boot/limine.conf ]]; then
	cp -a /boot/limine.conf "/boot/limine.conf.bak-before-intel-uki-$(date +%Y%m%d-%H%M%S)"
	"${root}/scripts/graphics/limine-set-default-uki.sh"
fi

echo
echo "UKI rebuilt with nvidia-off policy."
echo "Next: macOS Intel NVRAM if needed -> cold off -> boot UKI / Intel probe entry."
echo "Verify: sudo ${root}/scripts/graphics/verify-intel-uki-boot.sh"
