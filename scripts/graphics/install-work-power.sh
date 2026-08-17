#!/usr/bin/env bash
# Desk power profile for MacBookPro11,3 (Debian and CachyOS).
# Keeps the GT 750M awake for native HDMI/TB. Does not auto-sleep it
# on battery (this machine is not used on a commute). Does not force
# max backlight on an Intel lid.
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

install -d /etc/retinaforge
install -Dm644 "${root}/scripts/graphics/retinaforge-power-policy.conf" /etc/retinaforge/power-policy.conf

install -Dm755 "${root}/scripts/graphics/retinaforge-power-policy.sh" /usr/local/sbin/retinaforge-power-policy.sh
install -Dm755 "${root}/scripts/graphics/retinaforge-work-idle.sh" /usr/local/sbin/retinaforge-work-idle.sh
install -Dm755 "${root}/scripts/graphics/retinaforge-on-battery.sh" /usr/local/sbin/retinaforge-on-battery.sh
install -Dm755 "${root}/scripts/graphics/retinaforge-on-ac.sh" /usr/local/sbin/retinaforge-on-ac.sh
install -Dm755 "${root}/scripts/graphics/work-displays.sh" /usr/local/sbin/retinaforge-work-displays.sh
install -Dm755 "${root}/scripts/graphics/retinaforge-gmux-backlight-floor.sh" /usr/local/sbin/retinaforge-gmux-backlight-floor.sh
install -Dm755 "${root}/scripts/graphics/gmux-backlight-max.sh" /usr/local/sbin/gmux-backlight-max.sh
install -Dm644 "${root}/scripts/graphics/retinaforge-power-policy.service" /etc/systemd/system/retinaforge-power-policy.service
install -Dm644 "${root}/scripts/graphics/retinaforge-on-battery.service" /etc/systemd/system/retinaforge-on-battery.service
install -Dm644 "${root}/scripts/graphics/retinaforge-on-ac.service" /etc/systemd/system/retinaforge-on-ac.service
install -Dm644 "${root}/scripts/graphics/retinaforge-gmux-backlight-floor.service" /etc/systemd/system/retinaforge-gmux-backlight-floor.service
install -Dm644 "${root}/scripts/graphics/retinaforge-gmux-backlight-floor-session.service" /etc/systemd/system/retinaforge-gmux-backlight-floor-session.service
install -Dm644 "${root}/scripts/graphics/gmux-backlight-max.service" /etc/systemd/system/gmux-backlight-max.service
install -Dm644 "${root}/scripts/graphics/gmux-backlight-max-session.service" /etc/systemd/system/gmux-backlight-max-session.service
install -Dm644 "${root}/scripts/graphics/99-retinaforge-power.rules" /etc/udev/rules.d/99-retinaforge-power.rules

systemctl disable --now retinaforge-work-idle.service 2>/dev/null || true
rm -f /etc/systemd/system/retinaforge-work-idle.service

systemctl daemon-reload
systemctl enable retinaforge-power-policy.service
systemctl enable retinaforge-gmux-backlight-floor.service
systemctl enable retinaforge-gmux-backlight-floor-session.service
# NVIDIA-recovery force-max; the script no-ops while the lid is i915.
systemctl enable gmux-backlight-max.service gmux-backlight-max-session.service 2>/dev/null || true
if command -v udevadm >/dev/null 2>&1; then
	udevadm control --reload-rules 2>/dev/null || true
fi

/usr/local/sbin/retinaforge-power-policy.sh apply 2>/dev/null || true
/usr/local/sbin/retinaforge-gmux-backlight-floor.sh 2>/dev/null || true

echo "desk power profile installed (750M stays awake for monitors; no commute auto-sleep)."
/usr/local/sbin/retinaforge-power-policy.sh status || true
