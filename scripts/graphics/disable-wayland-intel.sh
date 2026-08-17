#!/usr/bin/env bash
# Restore Plasma X11 autologin (undo enable-wayland-intel.sh).
set -euo pipefail

here="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck source=wayland-sddm-lib.sh
source "${here}/wayland-sddm-lib.sh"
stash=/var/lib/retinaforge/sddm-stash
marker='# managed-by: retinaforge-wayland'

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

rm -f /etc/sddm.conf.d/99-retinaforge-wayland.conf
if [[ -f /etc/sddm.conf ]] && grep -qxF "$marker" /etc/sddm.conf; then
	rm -f /etc/sddm.conf
fi

if [[ -d $stash ]]; then
	for f in 10-x11.conf 10-intel.conf; do
		if [[ -f $stash/$f ]]; then
			mv -f "$stash/$f" "/etc/sddm.conf.d/$f"
		fi
	done
fi
# Restore in-place rename leftovers from older enable scripts.
for f in /etc/sddm.conf.d/10-x11.conf.disabled-for-wayland /etc/sddm.conf.d/10-intel.conf.disabled-for-wayland; do
	[[ -f $f ]] && mv "$f" "${f%.disabled-for-wayland}"
done

autologin="$(rf_sddm_autologin_file)"
user="$(rf_sddm_autologin_user)"
x11session="$(rf_x11_plasma_session)"
if [[ -n $user ]]; then
	printf '%s\n' '[Autologin]' "User=${user}" "Session=${x11session}" >"$autologin"
	cat >/var/lib/sddm/state.conf <<EOF
[Last]
User=${user}
Session=/usr/share/xsessions/${x11session}
EOF
elif [[ -f /var/lib/sddm/state.conf ]]; then
	sed -i "s|Session=/usr/share/wayland-sessions/.*|Session=/usr/share/xsessions/${x11session}|" \
		/var/lib/sddm/state.conf
fi

systemctl reset-failed sddm.service || true
if [[ -f ${here}/sddm-free-vt.sh ]]; then
	bash "${here}/sddm-free-vt.sh" || true
elif [[ -x /usr/local/sbin/retinaforge-sddm-free-vt ]]; then
	/usr/local/sbin/retinaforge-sddm-free-vt || true
fi
sleep 10
systemctl reset-failed sddm.service || true
systemctl start sddm.service
echo "restored ${x11session} autologin"
