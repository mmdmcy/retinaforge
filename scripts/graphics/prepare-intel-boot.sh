#!/bin/sh
# prepare-intel-boot.sh — one-shot prep for an Intel-first UKI boot on mbp113
#
# 1. Set gpu-policy (and best-effort gpu-power-prefs) to Intel
# 2. Ensure Limine defaults to the UKI / apple_set_os entry
# 3. Max GMUX backlight (black-panel recovery aid)
# 4. Optional reboot
#
# Best results: run set-gpu-power-prefs-intel.sh from macOS first, then cold
# power-off, then boot the UKI entry. This script covers the Linux-side prep.
#
# See docs/graphics/intel-first-repro.md

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
limine_conf=/boot/limine.conf
uki_entry_marker='uki-apple-set-os'
reboot_after=0

usage() {
	echo "usage: sudo $0 [--reboot]" >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case "$1" in
	--reboot) reboot_after=1 ;;
	-h|--help) usage ;;
	*) echo "unknown arg: $1" >&2; usage ;;
	esac
	shift
done

if [ "$(id -u)" -ne 0 ]; then
	echo "run as root: sudo $0 [--reboot]" >&2
	exit 1
fi

"$root/scripts/graphics/set-gpu-policy-intel.py"
/usr/local/sbin/gmux-backlight-max.sh 2>/dev/null || "$root/scripts/graphics/gmux-backlight-max.sh"

if [ -f "$limine_conf" ]; then
	cp -a "$limine_conf" "${limine_conf}.bak-before-intel-$(date +%Y%m%d-%H%M%S)"
	"$root/scripts/graphics/limine-set-default-uki.sh"
else
	echo "warn: $limine_conf missing" >&2
fi

echo
echo "Next: reboot into the Limine entry labeled UKI / Intel probe."
echo "After boot, run: sudo $root/scripts/graphics/check-intel-first-panel.sh"

if [ "$reboot_after" -eq 1 ]; then
	echo "Rebooting in 5 seconds (Ctrl-C on console to abort)..."
	sleep 5
	systemctl reboot
fi
