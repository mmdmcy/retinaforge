#!/usr/bin/env bash
# Install Intel DRM pin + Wayland session files. Does not change SDDM default.
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

install -Dm644 "${root}/scripts/graphics/61-retinaforge-intel-drm.rules" \
	/etc/udev/rules.d/61-retinaforge-intel-drm.rules
install -Dm644 "${root}/scripts/graphics/99-intel-drm.conf" \
	/etc/environment.d/99-intel-drm.conf
install -Dm644 "${root}/scripts/graphics/hyprland-retinaforge.conf" \
	/usr/local/share/retinaforge/hyprland-retinaforge.conf
install -Dm644 "${root}/scripts/graphics/hyprland-retinaforge.lua" \
	/usr/local/share/retinaforge/hyprland-retinaforge.lua
echo "Omarchy Lua pin: /usr/local/share/retinaforge/hyprland-retinaforge.lua"
install -Dm644 "${root}/scripts/graphics/hyprland-intel.conf" \
	/usr/local/share/retinaforge/hyprland-intel.conf
install -Dm755 "${root}/scripts/graphics/retinaforge-hyprland-intel" \
	/usr/local/bin/retinaforge-hyprland-intel
install -Dm755 "${root}/scripts/graphics/retinaforge-hypr-term" \
	/usr/local/bin/retinaforge-hypr-term
install -Dm755 "${root}/scripts/graphics/retinaforge-hypr-run" \
	/usr/local/bin/retinaforge-hypr-run
install -Dm755 "${root}/scripts/graphics/retinaforge-hypr-files" \
	/usr/local/bin/retinaforge-hypr-files
install -Dm755 "${root}/scripts/graphics/retinaforge-brightness" \
	/usr/local/bin/retinaforge-brightness
install -Dm644 "${root}/scripts/graphics/waybar-config.json" \
	/usr/local/share/retinaforge/waybar/config.json
install -Dm644 "${root}/scripts/graphics/waybar-style.css" \
	/usr/local/share/retinaforge/waybar/style.css
install -Dm644 "${root}/scripts/graphics/hid-apple-command-super.conf" \
	/etc/modprobe.d/retinaforge-hid-apple.conf
if [[ -w /sys/module/hid_apple/parameters/swap_opt_cmd ]]; then
	printf '0\n' >/sys/module/hid_apple/parameters/swap_opt_cmd || true
fi
if [[ -w /sys/module/hid_apple/parameters/fnmode ]]; then
	printf '1\n' >/sys/module/hid_apple/parameters/fnmode || true
fi
install -Dm644 "${root}/scripts/graphics/weston-intel.ini" \
	/usr/local/share/retinaforge/weston-intel.ini
install -Dm755 "${root}/scripts/graphics/retinaforge-weston-intel" \
	/usr/local/bin/retinaforge-weston-intel
install -Dm755 "${root}/scripts/graphics/sddm-free-vt.sh" \
	/usr/local/sbin/retinaforge-sddm-free-vt
install -Dm755 "${root}/scripts/graphics/plasma-intel-drm.sh" \
	/etc/xdg/plasma-workspace/env/retinaforge-intel-drm.sh

if command -v udevadm >/dev/null 2>&1; then
	udevadm control --reload-rules
	udevadm trigger --subsystem-match=drm --action=add 2>/dev/null || true
fi

if command -v Hyprland >/dev/null 2>&1; then
	install -Dm644 "${root}/scripts/graphics/hyprland-intel.desktop" \
		/usr/share/wayland-sessions/hyprland-intel.desktop
	echo "Hyprland session: hyprland-intel.desktop (SDDM default unchanged)."
else
	echo "Hyprland not installed; DRM pin is in place for Plasma Wayland / Weston."
fi

if command -v weston >/dev/null 2>&1; then
	install -Dm644 "${root}/scripts/graphics/weston-intel.desktop" \
		/usr/share/wayland-sessions/weston-intel.desktop
	echo "Weston session: weston-intel.desktop (SDDM default unchanged)."
fi

if [[ -e /dev/dri/intel-igpu ]]; then
	echo "intel-igpu -> $(readlink -f /dev/dri/intel-igpu)"
else
	echo "warning: /dev/dri/intel-igpu missing until udev add (or reboot)" >&2
fi
