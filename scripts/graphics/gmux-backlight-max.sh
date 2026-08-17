#!/bin/sh
# NVIDIA-recovery path: force gmux to max so a black lid is not "just dim".
# Intel lid: do not run — max brightness is extra heat and fights Plasma.
set -eu

fb="$(tr -d '\n' </sys/class/graphics/fb0/name 2>/dev/null || true)"
case $fb in
*i915*) exit 0 ;;
esac

backlight="/sys/class/backlight/gmux_backlight/brightness"
max="/sys/class/backlight/gmux_backlight/max_brightness"

[ -w "$backlight" ] || exit 0
[ -r "$max" ] || exit 0

value="$(cat "$max")"
printf '%s' "$value" >"$backlight"
