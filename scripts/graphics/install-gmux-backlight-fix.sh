#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "run as root: sudo $0" >&2
	exit 1
fi

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
install -D -m 0755 "$root/scripts/graphics/gmux-backlight-max.sh" /usr/local/sbin/gmux-backlight-max.sh
install -D -m 0644 "$root/scripts/graphics/gmux-backlight-max.service" /etc/systemd/system/gmux-backlight-max.service
install -D -m 0644 "$root/scripts/graphics/gmux-backlight-max-session.service" /etc/systemd/system/gmux-backlight-max-session.service

systemctl daemon-reload
systemctl enable gmux-backlight-max.service gmux-backlight-max-session.service
systemctl restart gmux-backlight-max.service gmux-backlight-max-session.service

if command -v xfconf-query >/dev/null 2>&1 && id -u "${SUDO_USER:-}" >/dev/null 2>&1; then
	user="${SUDO_USER}"
	dbus_address="$(sudo -u "$user" -H printenv DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true)"
	if [ -n "$dbus_address" ]; then
		sudo -u "$user" -H env DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
			xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/brightness-switch-restore-on-exit -s 0
	fi
fi

/usr/local/sbin/gmux-backlight-max.sh
echo "gmux backlight fix installed"
