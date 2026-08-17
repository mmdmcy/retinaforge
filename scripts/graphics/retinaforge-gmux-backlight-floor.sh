#!/bin/sh
# On the Intel UKI path: if gmux brightness is nearly off, raise it to a
# dim-but-visible floor. Never force max (that costs heat and battery).
set -eu

backlight="/sys/class/backlight/gmux_backlight/brightness"
actual="/sys/class/backlight/gmux_backlight/actual_brightness"
maxf="/sys/class/backlight/gmux_backlight/max_brightness"

fb="$(tr -d '\n' </sys/class/graphics/fb0/name 2>/dev/null || true)"
case $fb in
*i915*) ;;
*) exit 0 ;;
esac

[ -w "$backlight" ] || exit 0
[ -r "$maxf" ] || exit 0

max="$(cat "$maxf")"
cur="$(cat "$actual" 2>/dev/null || cat "$backlight")"
# ~8% of 1023. Below this the panel often looks "off" on this GMUX.
floor=80
if [ "${cur:-0}" -lt "$floor" ]; then
	printf '%s' "$floor" >"$backlight"
fi
