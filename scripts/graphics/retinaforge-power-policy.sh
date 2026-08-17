#!/usr/bin/env bash
# Desk power policy for MacBookPro11,3 (Intel lid).
#
# Native HDMI / Thunderbolt outputs live on the GT 750M. This machine
# is used at a desk, not on a commute, so the default is to keep that
# chip awake and the platform on balanced. Sleeping it is a manual
# tray/CLI action. Never writes IGD/DIS.
#
# Recreatable on Debian and CachyOS: DMI + i915 framebuffer guards only.
# No CachyOS cmdline token required.
set -euo pipefail

COMMUTE_SLEEP=0
if [[ -r /etc/retinaforge/power-policy.conf ]]; then
	# shellcheck disable=SC1091
	. /etc/retinaforge/power-policy.conf
fi

product="$(tr -d '\n' </sys/class/dmi/id/product_name 2>/dev/null || true)"
if [[ ${product} != MacBookPro11,3 ]]; then
	exit 0
fi

cmd="${1:-apply}"

is_intel_lid() {
	local fb
	fb="$(tr -d '\n' </sys/class/graphics/fb0/name 2>/dev/null || true)"
	[[ $fb == *i915* ]]
}

mains_online() {
	local d t on
	for d in /sys/class/power_supply/*; do
		[[ -r ${d}/type ]] || continue
		t="$(tr -d '\n' <"${d}/type" || true)"
		[[ $t == Mains ]] || continue
		on="$(tr -d '\n' <"${d}/online" 2>/dev/null || true)"
		if [[ $on == 1 ]]; then
			return 0
		fi
	done
	return 1
}

has_external_display() {
	local s name st
	shopt -s nullglob
	for s in /sys/class/drm/card*-*/status; do
		name="${s%/*}"
		name="${name##*/}"
		case $name in
		*eDP*) continue ;;
		esac
		st="$(tr -d '\n' <"$s" || true)"
		if [[ $st == connected ]]; then
			shopt -u nullglob
			return 0
		fi
	done
	shopt -u nullglob
	return 1
}

ensure_switch() {
	if [[ ! -e /sys/kernel/debug/vgaswitcheroo/switch ]]; then
		mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug || true
	fi
	switch=/sys/kernel/debug/vgaswitcheroo/switch
	if [[ ! -w $switch ]]; then
		echo "vgaswitcheroo not writable yet" >&2
		return 1
	fi
}

read_switch() {
	cat "$switch" 2>/dev/null || true
}

igd_selected() {
	grep -q 'IGD:+' <<<"$1"
}

dis_off() {
	grep -Eq 'DIS:[[:space:]]*:Off' <<<"$1"
}

dis_pwr() {
	grep -Eq 'DIS:[[:space:]]*:Pwr' <<<"$1"
}

set_ppd() {
	local profile=$1
	command -v powerprofilesctl >/dev/null 2>&1 || return 0
	powerprofilesctl set "$profile" >/dev/null 2>&1 || true
}

write_dis() {
	local want=$1 sw
	ensure_switch || return 1
	sw="$(read_switch)"
	if ! igd_selected "$sw"; then
		return 0
	fi
	case $want in
	OFF)
		if dis_off "$sw"; then
			return 0
		fi
		printf 'OFF\n' >"$switch"
		sw="$(read_switch)"
		if ! dis_off "$sw"; then
			echo "switcheroo OFF did not park DIS" >&2
			return 1
		fi
		;;
	ON)
		if dis_pwr "$sw"; then
			return 0
		fi
		printf 'ON\n' >"$switch"
		sw="$(read_switch)"
		if dis_off "$sw"; then
			echo "switcheroo ON did not wake DIS" >&2
			return 1
		fi
		;;
	*)
		echo "internal: bad write_dis $want" >&2
		return 1
		;;
	esac
}

desk() {
	is_intel_lid || return 0
	write_dis ON
	set_ppd balanced
}

commute() {
	is_intel_lid || return 0
	write_dis OFF
	set_ppd power-saver
}

apply() {
	is_intel_lid || return 0
	if mains_online || has_external_display || [[ ${COMMUTE_SLEEP} != 1 ]]; then
		desk
	else
		commute
	fi
}

status() {
	printf 'product=%s\n' "$product"
	printf 'fb0=%s\n' "$(tr -d '\n' </sys/class/graphics/fb0/name 2>/dev/null || true)"
	if mains_online; then
		echo 'mains=1'
	else
		echo 'mains=0'
	fi
	if has_external_display; then
		echo 'external=1'
	else
		echo 'external=0'
	fi
	printf 'commute_sleep=%s\n' "$COMMUTE_SLEEP"
	if command -v powerprofilesctl >/dev/null 2>&1; then
		printf 'ppd=%s\n' "$(powerprofilesctl get 2>/dev/null || true)"
	else
		echo 'ppd=absent'
	fi
	ensure_switch 2>/dev/null || true
	if [[ -n ${switch:-} && -r $switch ]]; then
		echo '---switch---'
		read_switch
	fi
	echo '---drm---'
	local s
	shopt -s nullglob
	for s in /sys/class/drm/card*-*/status; do
		printf '%s=%s\n' "${s%/*}" "$(tr -d '\n' <"$s" || true)"
	done
	shopt -u nullglob
}

case $cmd in
apply) apply ;;
desk) desk ;;
commute) commute ;;
status) status ;;
*)
	echo "usage: $0 apply|desk|commute|status" >&2
	exit 2
	;;
esac
