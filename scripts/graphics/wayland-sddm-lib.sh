#!/usr/bin/env bash
# Shared SDDM / Plasma session helpers. Sourced by enable/disable-wayland.
# Do not hardcode a login name.

rf_sddm_autologin_file() {
	printf '%s\n' /etc/sddm.conf.d/autologin.conf
}

rf_sddm_autologin_user() {
	local f user
	f="$(rf_sddm_autologin_file)"
	if [[ -f $f ]]; then
		user="$(awk -F= '/^User=/{print $2; exit}' "$f")"
		user="${user// /}"
		if [[ -n $user ]]; then
			printf '%s\n' "$user"
			return 0
		fi
	fi
	if [[ -n ${SUDO_USER:-} && $SUDO_USER != root ]]; then
		printf '%s\n' "$SUDO_USER"
		return 0
	fi
	# First human account (uid >= 1000, not nobody/nfsnobody).
	getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }'
}

rf_wayland_plasma_session() {
	local s
	for s in plasma.desktop plasmawayland.desktop; do
		if [[ -e /usr/share/wayland-sessions/$s ]]; then
			printf '%s\n' "$s"
			return 0
		fi
	done
	return 1
}

rf_x11_plasma_session() {
	local s
	for s in plasmax11.desktop plasma.desktop; do
		if [[ -e /usr/share/xsessions/$s ]]; then
			printf '%s\n' "$s"
			return 0
		fi
	done
	printf '%s\n' plasmax11.desktop
}

rf_kwin_wayland_bin() {
	local p
	for p in /usr/bin/kwin_wayland /usr/lib/kwin_wayland; do
		if [[ -x $p ]]; then
			printf '%s\n' "$p"
			return 0
		fi
	done
	return 1
}

rf_kwin_greeter_cmd() {
	local bin
	bin="$(rf_kwin_wayland_bin)" || return 1
	printf 'env KWIN_DRM_DEVICES=/dev/dri/intel-igpu KWIN_DRM_NO_AMS=1 KWIN_DRM_USE_MODIFIERS=0 KWIN_DRM_DISABLE_TRIPLE_BUFFERING=1 %s --drm --no-lockscreen --no-global-shortcuts --locale1\n' "$bin"
}
