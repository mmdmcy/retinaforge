#!/usr/bin/env bash
# Start the tray plate inside an already-running graphical session.
# Used after install-from-SSH. Normal logins use XDG autostart instead.
set -euo pipefail

if ((EUID != 0)); then
	echo "run as root: sudo $0 [user]" >&2
	exit 1
fi

user="${1:-}"
if [[ -z $user ]]; then
	user="$(loginctl list-sessions --no-legend | awk '/seat0/ {print $3; exit}')"
fi
if [[ -z $user ]]; then
	echo "no seat0 user" >&2
	exit 1
fi
uid="$(id -u "$user")"

pid="$(pgrep -u "$user" -n plasmashell || true)"
if [[ -z $pid ]]; then
	pid="$(pgrep -u "$user" -n kwin_x11 || true)"
fi
if [[ -z $pid ]]; then
	echo "no plasmashell/kwin for $user" >&2
	exit 1
fi

display=":0"
xauth=""
runtime="/run/user/${uid}"
dbus="unix:path=${runtime}/bus"
home="$(getent passwd "$user" | cut -d: -f6)"
while IFS= read -r line; do
	case "$line" in
	DISPLAY=*) display="${line#DISPLAY=}" ;;
	XAUTHORITY=*) xauth="${line#XAUTHORITY=}" ;;
	XDG_RUNTIME_DIR=*) runtime="${line#XDG_RUNTIME_DIR=}" ;;
	DBUS_SESSION_BUS_ADDRESS=*) dbus="${line#DBUS_SESSION_BUS_ADDRESS=}" ;;
	HOME=*) home="${line#HOME=}" ;;
	esac
done < <(tr '\0' '\n' <"/proc/${pid}/environ")

if [[ -z $xauth || ! -e $xauth ]]; then
	echo "no usable XAUTHORITY from pid $pid" >&2
	exit 1
fi

pkill -u "$user" -f /usr/local/share/retinaforge/mbp-panel/retinaforge-mbp-panel.py 2>/dev/null || true
sleep 0.2

runuser -u "$user" -- env DISPLAY="$display" XAUTHORITY="$xauth" \
	XDG_RUNTIME_DIR="$runtime" DBUS_SESSION_BUS_ADDRESS="$dbus" HOME="$home" \
	QT_QPA_PLATFORM=xcb QT_XCB_GL_INTEGRATION=none \
	bash -c 'nohup /usr/local/bin/retinaforge-mbp-panel >/dev/null 2>&1 </dev/null & disown'
echo "started retinaforge-mbp-panel for $user on $display"
