#!/usr/bin/env bash
# One-shot Wayland bring-up (does not persist unless KEEP=1).
# Prefer the persistent path:
#   sudo ./scripts/graphics/enable-wayland-intel.sh
#
#   sudo SESSION=plasma.desktop ./scripts/graphics/try-wayland-intel.sh
set -euo pipefail

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

SESSION="${SESSION:-plasma.desktop}"
KEEP="${KEEP:-0}"
WAIT_SEC="${WAIT_SEC:-30}"
AUTOLOGIN=/etc/sddm.conf.d/autologin.conf
BACKUP=/var/lib/retinaforge/sddm-stash/autologin.conf.bak-retinaforge-wayland
TRYDROP=/etc/sddm.conf.d/99-retinaforge-wayland-try.conf
X11CONF=/etc/sddm.conf.d/10-x11.conf
INTELCONF=/etc/sddm.conf.d/10-intel.conf
IGPU=/dev/dri/intel-igpu
GREETER=/usr/bin/sddm-greeter-qt6
[[ -x $GREETER ]] || GREETER=/usr/bin/sddm-greeter

restore() {
	rm -f "$TRYDROP"
	[[ -f ${X11CONF}.wayland-try ]] && mv "${X11CONF}.wayland-try" "$X11CONF"
	[[ -f ${INTELCONF}.wayland-try ]] && mv "${INTELCONF}.wayland-try" "$INTELCONF"
	if [[ ${KEEP} == 1 ]]; then
		echo "KEEP=1: leaving Session=${SESSION}"
		return 0
	fi
	if [[ -f $BACKUP ]]; then
		cp -a "$BACKUP" "$AUTOLOGIN"
	fi
	systemctl restart sddm
	echo "restored previous SDDM autologin / X11 greeter"
}

trap restore EXIT

if [[ ! -f $AUTOLOGIN ]]; then
	echo "missing $AUTOLOGIN" >&2
	exit 1
fi
mkdir -p "$(dirname "$BACKUP")"
cp -a "$AUTOLOGIN" "$BACKUP"
user="$(awk -F= '/^User=/{print $2; exit}' "$BACKUP")"
if [[ -z $user ]]; then
	echo "no User= in $AUTOLOGIN" >&2
	exit 1
fi
if [[ ! -e $IGPU ]]; then
	echo "missing $IGPU (install-wayland-intel.sh / udev)" >&2
	exit 1
fi
if [[ $SESSION == hyprland-intel.desktop && ! -e /usr/share/wayland-sessions/hyprland-intel.desktop ]]; then
	echo "missing hyprland-intel.desktop" >&2
	exit 1
fi
if [[ $SESSION == plasma.desktop && ! -e /usr/share/wayland-sessions/plasma.desktop ]]; then
	echo "missing plasma.desktop" >&2
	exit 1
fi
if [[ ! -x $GREETER ]]; then
	echo "no sddm greeter binary" >&2
	exit 1
fi

printf '%s\n' '[Autologin]' "User=${user}" "Session=${SESSION}" >"$AUTOLOGIN"
[[ -f $X11CONF ]] && mv "$X11CONF" "${X11CONF}.wayland-try"
[[ -f $INTELCONF ]] && mv "$INTELCONF" "${INTELCONF}.wayland-try"
cat >"$TRYDROP" <<EOF
[General]
DisplayServer=wayland
RememberLastSession=false
ReuseSession=false
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell
[Wayland]
CompositorCommand=weston --backend=drm --shell=kiosk --idle-time=0
EOF

echo "starting SDDM Wayland greeter + session ${SESSION}"
systemctl restart sddm
sleep "$WAIT_SEC"

echo '=== loginctl seat0 ==='
loginctl list-sessions --no-legend || true
sess="$(loginctl list-sessions --no-legend | awk '/seat0/{print $1; exit}')"
if [[ -n $sess ]]; then
	loginctl show-session "$sess" -p Type -p Desktop -p Display -p Name -p Class || true
fi
echo '=== processes ==='
pgrep -af kwin_wayland || true
pgrep -af Hyprland || true
pgrep -af weston || true
pgrep -af startplasma-wayland || true
pgrep -af sddm-greeter || true
echo '=== fb / drm ==='
cat /sys/class/graphics/fb0/name 2>/dev/null || true
readlink -f "$IGPU" || true
echo '=== sddm status ==='
systemctl is-active sddm || true
echo '=== wayland-session.log ==='
home="$(getent passwd "$user" | cut -d: -f6)"
if [[ -f ${home}/.local/share/sddm/wayland-session.log ]]; then
	tail -80 "${home}/.local/share/sddm/wayland-session.log"
fi
echo '=== journal ==='
journalctl -u sddm -b --since '2 min ago' --no-pager | tail -80 || true
journalctl -b --since '2 min ago' --no-pager | grep -iE 'kwin_wayland|Hyprland|aquamarine|startplasma-wayland|wayland-session' | tail -40 || true
