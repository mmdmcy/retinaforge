#!/usr/bin/env bash
# enable-intel-daily.sh — target config for Intel-first UKI daily boot on mbp113.
#
# - UKI auto-default (limine)
# - proprietary NVIDIA blocked; nouveau allowed for GMUX switcheroo
# - Xorg on Intel modesetting
#
# Recovery only (SSH, no local display): boot macOS (Option) or Limine →
# linux-cachyos-lts after disable-nvidia-off.sh. Not the product goal.

set -euo pipefail

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

install -Dm644 "${root}/scripts/graphics/nvidia-off-modprobe.conf" /etc/modprobe.d/retinaforge-nvidia-off.conf
install -Dm644 "${root}/scripts/graphics/apple-gmux-intel.conf" /etc/modprobe.d/retinaforge-apple-gmux-intel.conf
install -Dm644 "${root}/scripts/graphics/apple-gmux-softdep.conf" /etc/modprobe.d/retinaforge-apple-gmux-softdep.conf
install -Dm644 "${root}/scripts/graphics/retinaforge-gmux-nouveau.service" /etc/systemd/system/retinaforge-gmux-nouveau.service
systemctl daemon-reload
systemctl enable retinaforge-gmux-nouveau.service
rm -f /etc/systemd/system/retinaforge-nouveau.service
systemctl disable retinaforge-nouveau.service 2>/dev/null || true
# Lab script; not part of Intel mux path but can touch switcheroo/backlight after boot.
if systemctl list-unit-files mbp-cool-idle.service &>/dev/null; then
	systemctl disable --now mbp-cool-idle.service 2>/dev/null || true
fi
rm -f /etc/modprobe.d/retinaforge-intel-panel.conf /etc/modprobe.d/retinaforge-intel-panel.conf.disabled 2>/dev/null || true

if [[ -f /etc/X11/xorg.conf.d/30-nvidia-composition.conf ]]; then
	mv /etc/X11/xorg.conf.d/30-nvidia-composition.conf /etc/X11/xorg.conf.d/30-nvidia-composition.conf.disabled-intel-daily
fi

install -Dm644 "${root}/scripts/graphics/xorg-intel-panel.conf" /etc/X11/xorg.conf.d/40-intel-panel.conf

"${root}/scripts/graphics/limine-set-default-uki.sh"
install -Dm755 "${root}/scripts/graphics/retinaforge-log-gpu-policy.sh" /usr/local/sbin/retinaforge-log-gpu-policy.sh
install -Dm644 "${root}/scripts/graphics/retinaforge-log-gpu-policy.service" /etc/systemd/system/retinaforge-log-gpu-policy.service
systemctl enable retinaforge-log-gpu-policy.service
/usr/local/sbin/gmux-backlight-max.sh 2>/dev/null || "${root}/scripts/graphics/gmux-backlight-max.sh"

depmod -a
echo "Intel-daily target config installed. Reboot for a clean UKI + nvidia-off boot."
