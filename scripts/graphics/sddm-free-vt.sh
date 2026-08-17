#!/usr/bin/env bash
# Stop SDDM, drop leftover X11/Wayland helpers, reset systemd rate limit.
# Does not touch sshd or the caller's login shell.
set -euo pipefail

user="${1:-}"
if [[ -z $user ]]; then
	user="$(awk -F= '/^User=/{print $2; exit}' /etc/sddm.conf.d/autologin.conf 2>/dev/null || true)"
fi
if [[ -z $user ]]; then
	echo "sddm-free-vt: no autologin User=" >&2
	exit 1
fi

systemctl stop sddm.service || true
systemctl reset-failed sddm.service || true
systemctl stop getty@tty1.service 2>/dev/null || true

pkill -x sddm 2>/dev/null || true
pkill -f '/usr/lib/sddm/sddm-helper' 2>/dev/null || true
pkill -f '/usr/lib/sddm/sddm-helper-start-wayland' 2>/dev/null || true
pkill -x X 2>/dev/null || true
pkill -x Xorg 2>/dev/null || true

for proc in startplasma-x11 startplasma-wayland plasmashell kwin_x11 kwin_wayland Hyprland weston; do
	pkill -u "$user" -x "$proc" 2>/dev/null || true
done

sleep 2
systemctl reset-failed sddm.service || true
echo "sddm-free-vt: tty1/drm holders:"
fuser -v /dev/tty1 2>&1 || true
fuser -v /dev/dri/card1 2>&1 || true
echo "sddm-free-vt: remaining graphical:"
pgrep -af 'sddm|startplasma|kwin_|Hyprland|weston|Xorg' || true
