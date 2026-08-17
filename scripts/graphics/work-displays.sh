#!/usr/bin/env bash
# Wake the GT 750M so native HDMI / Thunderbolt outputs can appear.
# Does not move the GMUX. Does not configure layout — use the desktop
# display settings (or xrandr) after the connectors show connected.
set -euo pipefail

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

policy=/usr/local/sbin/retinaforge-power-policy.sh
if [[ ! -x $policy ]]; then
	policy="$(CDPATH= cd -- "$(dirname "$0")" && pwd)/retinaforge-power-policy.sh"
fi
"$policy" desk
sleep 2
echo '---drm---'
shopt -s nullglob
for s in /sys/class/drm/card*-*/status; do
	printf '%s=%s\n' "${s%/*}" "$(tr -d '\n' <"$s" || true)"
done
shopt -u nullglob
if command -v xrandr >/dev/null 2>&1 && [[ -n ${DISPLAY:-} ]]; then
	echo '---xrandr---'
	xrandr --query | awk '/connected|disconnected/'
fi
echo "Place screens in the desktop display settings. USB DisplayLink is a different path (present-on)."
