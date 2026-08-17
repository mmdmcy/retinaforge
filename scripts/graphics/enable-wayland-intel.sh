#!/usr/bin/env bash
# Switch this MacBookPro11,3 to Plasma Wayland on Iris Pro.
# SDDM 0.21 loads *every* file in sddm.conf.d (not only *.conf), in
# locale order, then /etc/sddm.conf last. Backup files in that directory
# previously overrode Autologin back to plasmax11.
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
# shellcheck source=wayland-sddm-lib.sh
source "${root}/scripts/graphics/wayland-sddm-lib.sh"
stash=/var/lib/retinaforge/sddm-stash
marker='# managed-by: retinaforge-wayland'

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

bash "${root}/scripts/graphics/install-wayland-intel.sh"

autologin="$(rf_sddm_autologin_file)"
user="$(rf_sddm_autologin_user)"
if [[ -z $user ]]; then
	echo "no autologin User= and no SUDO_USER / uid>=1000 account" >&2
	exit 1
fi
install -d /etc/sddm.conf.d
if [[ ! -e /dev/dri/intel-igpu ]]; then
	udevadm trigger --subsystem-match=drm --action=add 2>/dev/null || true
	sleep 1
fi
if [[ ! -e /dev/dri/intel-igpu ]]; then
	echo "missing /dev/dri/intel-igpu" >&2
	exit 1
fi

mkdir -p "$stash"
shopt -s nullglob
for f in /etc/sddm.conf.d/10-x11.conf \
	/etc/sddm.conf.d/10-intel.conf \
	/etc/sddm.conf.d/*.disabled-for-wayland \
	/etc/sddm.conf.d/*.wayland-try \
	/etc/sddm.conf.d/*.bak \
	/etc/sddm.conf.d/*.bak-* \
	/etc/sddm.conf.d/99-retinaforge-wayland-try.conf; do
	[[ -f $f ]] || continue
	mv -f "$f" "$stash/$(basename "$f")"
done
shopt -u nullglob
rm -f /etc/sddm.conf.d/99-retinaforge-wayland-try.conf

if [[ -f /etc/environment ]]; then
	sed -i \
		'/^KWIN_DRM_DEVICES=/d;/^KWIN_DRM_NO_AMS=/d;/^KWIN_DRM_USE_MODIFIERS=/d;/^KWIN_DRM_DISABLE_TRIPLE_BUFFERING=/d;/^AQ_DRM_DEVICES=/d;/^AQ_NO_ATOMIC=/d;/^WLR_DRM_DEVICES=/d;/^WLR_DRM_NO_ATOMIC=/d' \
		/etc/environment
	cat >>/etc/environment <<'EOF'
KWIN_DRM_DEVICES=/dev/dri/intel-igpu
KWIN_DRM_NO_AMS=1
KWIN_DRM_USE_MODIFIERS=0
KWIN_DRM_DISABLE_TRIPLE_BUFFERING=1
AQ_DRM_DEVICES=/dev/dri/intel-igpu
AQ_NO_ATOMIC=1
WLR_DRM_DEVICES=/dev/dri/intel-igpu
WLR_DRM_NO_ATOMIC=1
EOF
fi

# X11 bring-up masked this so startplasma could not use KWin Wayland.
systemctl -M "${user}@" --user unmask plasma-kwin_wayland.service 2>/dev/null || true

kwin_greeter=""
rf_kwin_greeter_cmd >/dev/null && kwin_greeter="$(rf_kwin_greeter_cmd)"
plasma_session=""
rf_wayland_plasma_session >/dev/null && plasma_session="$(rf_wayland_plasma_session)"

write_sddm() {
	local session=$1
	local greeter_cmd=$2
	printf '%s\n' '[Autologin]' "User=${user}" "Session=${session}" >"$autologin"
	cat >/etc/sddm.conf.d/99-retinaforge-wayland.conf <<EOF
[General]
DisplayServer=wayland
RememberLastSession=false
ReuseSession=false
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell,KWIN_DRM_DEVICES=/dev/dri/intel-igpu,KWIN_DRM_NO_AMS=1,KWIN_DRM_USE_MODIFIERS=0,KWIN_DRM_DISABLE_TRIPLE_BUFFERING=1

[Users]
RememberLastSession=false
ReuseSession=false

[Wayland]
CompositorCommand=${greeter_cmd}

[Autologin]
User=${user}
Session=${session}
Relogin=false
EOF
	# Loaded last — beats leftover drop-ins.
	cat >/etc/sddm.conf <<EOF
${marker}
[Autologin]
User=${user}
Session=${session}
Relogin=false

[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell,KWIN_DRM_DEVICES=/dev/dri/intel-igpu,KWIN_DRM_NO_AMS=1,KWIN_DRM_USE_MODIFIERS=0,KWIN_DRM_DISABLE_TRIPLE_BUFFERING=1

[Users]
RememberLastSession=false
ReuseSession=false

[Wayland]
CompositorCommand=${greeter_cmd}
EOF
	cat >/var/lib/sddm/state.conf <<EOF
[Last]
User=${user}
Session=/usr/share/wayland-sessions/${session}
EOF
}

compositor_running() {
	local session=$1
	case $session in
		weston-intel.desktop) pgrep -u "$user" -x weston >/dev/null ;;
		hyprland-intel.desktop) pgrep -u "$user" -x Hyprland >/dev/null ;;
		plasma.desktop | plasmawayland.desktop) pgrep -u "$user" -x kwin_wayland >/dev/null ;;
		*) return 1 ;;
	esac
}

try_once() {
	local session=$1
	local greeter_cmd=$2
	if [[ ! -e /usr/share/wayland-sessions/${session} ]]; then
		echo "skip ${session} (not installed)"
		return 1
	fi
	echo "try session=${session}"
	echo "sddm.conf.d after stash:"; ls -la /etc/sddm.conf.d/ || true
	write_sddm "$session" "$greeter_cmd"
	local since
	since="$(date --iso-8601=seconds)"
	bash "${root}/scripts/graphics/sddm-free-vt.sh" "$user"
	sleep 10
	systemctl reset-failed sddm.service || true
	systemctl start sddm.service || true
	if [[ $session == plasma.desktop || $session == plasmawayland.desktop ]]; then
		sleep 28
	else
		sleep 22
	fi
	if [[ $session == plasma.desktop || $session == plasmawayland.desktop ]] && journalctl --since "$since" --no-pager 2>/dev/null | grep -q 'Pageflip timed out'; then
		echo "plasma: pageflip timed out"
		return 1
	fi
	if compositor_running "$session"; then
		echo "wayland ok: session=${session}"
		return 0
	fi
	echo "failed: session=${session}"
	loginctl list-sessions --no-legend || true
	pgrep -af 'weston|Hyprland|kwin_wayland|startplasma' || true
	echo '--- autologin ---'; cat "$autologin"
	echo '--- /etc/sddm.conf ---'; cat /etc/sddm.conf
	echo '--- journal ---'
	journalctl -u sddm --since "$since" --no-pager | tail -50 || true
	home="$(getent passwd "$user" | cut -d: -f6)"
	if [[ -f ${home}/.local/share/sddm/wayland-session.log ]]; then
		echo '--- wayland-session.log ---'
		tail -80 "${home}/.local/share/sddm/wayland-session.log"
	fi
	return 1
}

kept=""
prefer="${PREFER:-plasma}"
if [[ $prefer == hyprland ]]; then
	if [[ -n $kwin_greeter ]] && try_once hyprland-intel.desktop "$kwin_greeter"; then
		kept=hyprland-intel.desktop
	elif [[ -n $plasma_session && -n $kwin_greeter ]] && try_once "$plasma_session" "$kwin_greeter"; then
		kept=$plasma_session
	elif [[ -n $kwin_greeter ]] && try_once weston-intel.desktop "$kwin_greeter"; then
		kept=weston-intel.desktop
	fi
else
	if [[ -n $plasma_session && -n $kwin_greeter ]] && try_once "$plasma_session" "$kwin_greeter"; then
		kept=$plasma_session
	elif [[ -n $kwin_greeter ]] && try_once weston-intel.desktop "$kwin_greeter"; then
		kept=weston-intel.desktop
	elif [[ -n $kwin_greeter ]] && try_once hyprland-intel.desktop "$kwin_greeter"; then
		kept=hyprland-intel.desktop
	fi
fi

if [[ -z $kept ]]; then
	echo "no Wayland compositor stayed up; restoring Plasma X11"
	bash "${root}/scripts/graphics/disable-wayland-intel.sh"
	exit 1
fi

echo "Wayland enabled: ${kept}. Revert: sudo ${root}/scripts/graphics/disable-wayland-intel.sh"
