#!/usr/bin/env bash
# enable-intel-daily.sh — target config for Intel-first UKI daily boot.
#
# - proprietary NVIDIA blocked; nouveau allowed for GMUX switcheroo
# - Xorg on Intel modesetting
# - DDI A 4-lane poke before i915 (Haswell GOP never sets the bit on DIS-first)
#
# Recovery only (SSH, no local display): boot macOS (Option) or Limine →
# linux-cachyos-lts after disable-nvidia-off.sh. Not the product goal.
# This script does not rewrite Limine; keep NVIDIA LTS as a numbered recovery
# entry and set default_entry to the Intel UKI after check-intel-first-panel.sh
# passes.

set -euo pipefail

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

install -Dm644 "${root}/scripts/graphics/nvidia-off-modprobe.conf" /etc/modprobe.d/retinaforge-nvidia-off.conf
install -Dm644 "${root}/scripts/graphics/apple-gmux-intel.conf" /etc/modprobe.d/retinaforge-apple-gmux-intel.conf
install -Dm644 "${root}/scripts/graphics/apple-gmux-softdep.conf" /etc/modprobe.d/retinaforge-apple-gmux-softdep.conf
# Handoff experiment wedges boot — keep off on the default Intel daily path.
systemctl disable retinaforge-gmux-edp-handoff.service 2>/dev/null || true
rm -f /etc/systemd/system/retinaforge-gmux-edp-handoff.service
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
install -Dm644 "${root}/scripts/graphics/xorg-disable-nvidia.conf" /etc/X11/xorg.conf.d/50-disable-nvidia.conf

install -Dm755 "${root}/scripts/graphics/retinaforge-i915-ddi-4lanes.py" /usr/local/sbin/retinaforge-i915-ddi-4lanes.py
install -Dm644 "${root}/scripts/graphics/retinaforge-i915-ddi-4lanes.service" /etc/systemd/system/retinaforge-i915-ddi-4lanes.service
install -Dm644 "${root}/scripts/graphics/retinaforge-i915-ddi-4lanes-display-manager.conf" \
	/etc/systemd/system/display-manager.service.d/retinaforge-ddi-4lanes.conf
install -Dm644 "${root}/scripts/graphics/retinaforge-i915-ddi-4lanes-display-manager.conf" \
	/etc/systemd/system/sddm.service.d/retinaforge-ddi-4lanes.conf
systemctl daemon-reload
install -d /etc/retinaforge
printf 'intel-panel\n' >/etc/retinaforge/intel-panel
systemctl enable retinaforge-i915-ddi-4lanes.service

# Keep NVIDIA LTS as a numbered recovery entry. Do not rewrite Limine here:
# limine-set-default-uki.sh strips extra Intel UKI entries and forces entry 1.
install -Dm755 "${root}/scripts/graphics/retinaforge-log-gpu-policy.sh" /usr/local/sbin/retinaforge-log-gpu-policy.sh
install -Dm644 "${root}/scripts/graphics/retinaforge-log-gpu-policy.service" /etc/systemd/system/retinaforge-log-gpu-policy.service
systemctl enable retinaforge-log-gpu-policy.service
bash "${root}/scripts/graphics/install-work-power.sh"
bash "${root}/scripts/graphics/install-wayland-intel.sh"
/usr/local/sbin/retinaforge-gmux-backlight-floor.sh 2>/dev/null || \
	"${root}/scripts/graphics/retinaforge-gmux-backlight-floor.sh"

depmod -a
echo "Intel-daily target config installed (DDI 4-lane poke + Intel Xorg + desk power + Wayland DRM pin)."
echo "Rebuild the UKI, reboot it, then: sudo ${root}/scripts/graphics/enable-wayland-intel.sh"
