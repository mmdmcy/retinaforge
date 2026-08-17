#!/usr/bin/env bash
# check-wayland-intel.sh — verify Plasma (or fallback) Wayland on Iris Pro.
# Read-only. Exit 0 if seat0 is Wayland on i915; 1 if not.
set -euo pipefail

critical_fail=0
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; critical_fail=1; }
warn() { printf 'WARN  %s\n' "$*"; }
info() { printf 'INFO  %s\n' "$*"; }

if [[ "$(uname -s)" != Linux ]]; then
	echo "Linux only" >&2
	exit 2
fi

echo "=== MacBookPro11,3 Wayland (Intel lid) check ==="
echo

fb=""
if [[ -r /sys/class/graphics/fb0/name ]]; then
	fb="$(tr -d '\0' </sys/class/graphics/fb0/name)"
fi
info "fb0=${fb:-none}"
if [[ $fb == *i915* ]]; then
	pass "lid framebuffer is i915"
else
	fail "lid is not i915 (${fb:-none}) — Wayland on this chassis needs the Intel UKI path first"
fi

if [[ -e /dev/dri/intel-igpu ]]; then
	pass "intel-igpu -> $(readlink -f /dev/dri/intel-igpu)"
else
	fail "missing /dev/dri/intel-igpu (install-wayland-intel.sh udev rule)"
fi

edp_en=0
for en in /sys/class/drm/card*-eDP-*/enabled; do
	[[ -e $en ]] || continue
	if [[ $(cat "$en" 2>/dev/null) == enabled ]]; then
		edp_en=1
		info "$(basename "$(dirname "$en")") enabled"
	fi
done
if [[ $edp_en -eq 1 ]]; then
	pass "an eDP connector is enabled"
else
	fail "no enabled eDP"
fi

sess="$(loginctl list-sessions --no-legend 2>/dev/null | awk '/seat0/{print $1; exit}')"
if [[ -z ${sess:-} ]]; then
	fail "no seat0 session"
else
	typ="$(loginctl show-session "$sess" -p Type --value 2>/dev/null || true)"
	desk="$(loginctl show-session "$sess" -p Desktop --value 2>/dev/null || true)"
	info "seat0 session=$sess Type=$typ Desktop=$desk"
	if [[ $typ == wayland ]]; then
		pass "seat0 Type=wayland"
	else
		fail "seat0 Type=${typ:-unknown} (want wayland)"
	fi
fi

if pgrep -x kwin_wayland >/dev/null; then
	pass "kwin_wayland is running"
elif pgrep -x weston >/dev/null; then
	warn "weston is running (Wayland yes; Plasma did not stay up)"
elif pgrep -x Hyprland >/dev/null; then
	warn "Hyprland is running (Wayland yes; Plasma did not stay up)"
else
	fail "no known Wayland compositor (kwin_wayland / weston / Hyprland)"
fi

if pgrep -x plasmashell >/dev/null; then
	pass "plasmashell is running"
else
	warn "no plasmashell (bare compositor or session still starting)"
fi

if journalctl --since '5 min ago' --no-pager 2>/dev/null | grep -q 'Pageflip timed out'; then
	fail "kwin pageflip timeout in the last 5 minutes — do not re-enable i915.enable_dc"
else
	pass "no recent kwin pageflip timeout"
fi

if [[ -f /etc/sddm.conf ]] && grep -q 'DisplayServer=wayland' /etc/sddm.conf; then
	pass "SDDM /etc/sddm.conf DisplayServer=wayland"
elif grep -Rqs 'DisplayServer=wayland' /etc/sddm.conf.d 2>/dev/null; then
	info "DisplayServer=wayland in sddm.conf.d (confirm no later DisplayServer=x11)"
else
	warn "could not see DisplayServer=wayland in /etc/sddm.conf"
fi

if [[ $critical_fail -ne 0 ]]; then
	echo
	echo "Wayland check FAILED"
	exit 1
fi
echo
echo "Wayland check passed"
exit 0
