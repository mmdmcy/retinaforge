#!/usr/bin/env bash
# Recreate the MacBookPro11,3 Linux desktop from this repo.
#
#   sudo ./scripts/graphics/recreate-desktop.sh lid      # DDI poke, Xorg pin, power, DRM pin
#   sudo ./scripts/graphics/recreate-desktop.sh power    # desk 750M policy only
#   sudo ./scripts/graphics/recreate-desktop.sh wayland  # Plasma Wayland autologin
#   sudo ./scripts/graphics/recreate-desktop.sh hyprland # Hyprland autologin (CachyOS/SDDM)
#   sudo ./scripts/graphics/recreate-desktop.sh omarchy  # DRM pin + Lua snippet; no SDDM
#   sudo ./scripts/graphics/recreate-desktop.sh check    # lid + wayland verify
#   sudo ./scripts/graphics/recreate-desktop.sh all      # lid+power, then Plasma Wayland if fb is i915
#
# Does not rebuild a UKI or reboot. Lid pixels still need EFI-stub + force_igd.
# See docs/graphics/recreate.md
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cmd="${1:-}"

if ((EUID != 0)); then
	echo "run as root: sudo $0 {lid|power|wayland|hyprland|omarchy|check|all}" >&2
	exit 1
fi

usage() {
	sed -n '2,14p' "$0" | sed 's/^# \?//'
}

fb_is_i915() {
	local n=""
	[[ -r /sys/class/graphics/fb0/name ]] || return 1
	n="$(tr -d '\0' </sys/class/graphics/fb0/name)"
	[[ $n == *i915* ]]
}

case "$cmd" in
lid)
	bash "${root}/scripts/graphics/enable-intel-daily.sh"
	echo "Next: rebuild the Intel UKI (CachyOS: SKIP_LIMINE=1 ./scripts/graphics/build-apple-set-os-uki.sh)."
	echo "Debian: docs/graphics/recreate.md (ukify + patched apple-gmux)."
	echo "Then reboot that UKI and: sudo $0 check && sudo $0 wayland"
	;;
power)
	bash "${root}/scripts/graphics/install-work-power.sh"
	;;
wayland)
	bash "${root}/scripts/graphics/enable-wayland-intel.sh"
	;;
hyprland)
	PREFER=hyprland bash "${root}/scripts/graphics/enable-wayland-intel.sh"
	;;
omarchy)
	bash "${root}/scripts/graphics/enable-intel-daily.sh"
	echo "Omarchy: do not run enable-wayland-intel.sh (that is SDDM)."
	echo "After the Intel UKI lights the lid, add this LAST line to ~/.config/hypr/hyprland.lua:"
	echo '  dofile("/usr/local/share/retinaforge/hyprland-retinaforge.lua")'
	echo "Cook-book: docs/graphics/omarchy.md"
	;;
check)
	bash "${root}/scripts/graphics/check-intel-first-panel.sh"
	echo
	bash "${root}/scripts/graphics/check-wayland-intel.sh" || true
	;;
all)
	bash "${root}/scripts/graphics/enable-intel-daily.sh"
	if fb_is_i915; then
		bash "${root}/scripts/graphics/enable-wayland-intel.sh"
		bash "${root}/scripts/graphics/check-intel-first-panel.sh"
		bash "${root}/scripts/graphics/check-wayland-intel.sh"
	else
		echo "fb0 is not i915 yet — reboot the Intel UKI, then: sudo $0 wayland && sudo $0 check" >&2
		exit 1
	fi
	;;
*)
	usage
	exit 2
	;;
esac
