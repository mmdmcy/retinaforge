#!/usr/bin/env bash
# enable-intel-edp-handoff.sh — Intel daily boot via indexed GMUX eDP handoff.
#
# Unlike enable-intel-daily.sh (force_igd at module load), this profile keeps the
# panel on DIS/nouveau until link training completes, then switches to IGD before
# the display manager starts.
#
# Recovery: disable-nvidia-off.sh + Limine LTS, or touch /etc/retinaforge/skip-edp-handoff
# and reboot into the force_igd profile.

set -euo pipefail

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

install -Dm644 "${root}/scripts/graphics/nvidia-off-modprobe.conf" /etc/modprobe.d/retinaforge-nvidia-off.conf
install -Dm644 "${root}/scripts/graphics/apple-gmux-softdep.conf" /etc/modprobe.d/retinaforge-apple-gmux-softdep.conf
rm -f /etc/modprobe.d/retinaforge-apple-gmux-intel.conf

install -Dm755 "${root}/scripts/graphics/gmux-edp-handoff.sh" /usr/local/sbin/gmux-edp-handoff.sh
install -Dm644 "${root}/scripts/graphics/retinaforge-gmux-edp-handoff.service" /etc/systemd/system/retinaforge-gmux-edp-handoff.service
rm -f /etc/systemd/system/retinaforge-gmux-nouveau.service
systemctl disable retinaforge-gmux-nouveau.service 2>/dev/null || true
systemctl daemon-reload
systemctl enable retinaforge-gmux-edp-handoff.service

rm -f /etc/systemd/system/retinaforge-nouveau.service
systemctl disable retinaforge-nouveau.service 2>/dev/null || true

if systemctl list-unit-files mbp-cool-idle.service &>/dev/null; then
	systemctl disable --now mbp-cool-idle.service 2>/dev/null || true
fi
rm -f /etc/modprobe.d/retinaforge-intel-panel.conf /etc/modprobe.d/retinaforge-intel-panel.conf.disabled 2>/dev/null || true
rm -f /etc/retinaforge/skip-edp-handoff 2>/dev/null || true

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
echo "Intel eDP-handoff profile installed."
echo "Rebuild UKI: sudo INTEL_UKI_PROFILE=handoff ${root}/scripts/graphics/build-apple-set-os-uki.sh"
echo "Then cold reboot (macOS NVRAM prep optional)."
