#!/usr/bin/env bash
# disable-nvidia-off.sh — emergency SSH recovery only (re-enable NVIDIA for LTS boot).
# Primary lab goal remains Intel i915 panel; do not use this as a "daily driver" shortcut.

set -euo pipefail

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

mv /etc/modprobe.d/retinaforge-nvidia-off.conf /etc/modprobe.d/retinaforge-nvidia-off.conf.disabled 2>/dev/null || true
mv /etc/modprobe.d/retinaforge-apple-gmux-intel.conf /etc/modprobe.d/retinaforge-apple-gmux-intel.conf.disabled 2>/dev/null || true
rm -f /etc/retinaforge/intel-panel
if systemctl list-unit-files mbp-cool-idle.service &>/dev/null; then
	systemctl disable --now mbp-cool-idle.service 2>/dev/null || true
fi
if [[ -f /etc/X11/xorg.conf.d/30-nvidia-composition.conf.disabled-intel-daily ]]; then
	mv /etc/X11/xorg.conf.d/30-nvidia-composition.conf.disabled-intel-daily /etc/X11/xorg.conf.d/30-nvidia-composition.conf
fi
rm -f /etc/X11/xorg.conf.d/40-intel-panel.conf
rm -f /etc/X11/xorg.conf.d/50-disable-nvidia.conf
depmod -a
echo "nvidia-off disabled; NVIDIA Xorg restored. Reboot into linux-cachyos-lts."
