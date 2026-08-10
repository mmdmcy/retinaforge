#!/bin/sh
set -eu

backlight="/sys/class/backlight/gmux_backlight/brightness"
max="/sys/class/backlight/gmux_backlight/max_brightness"

[ -w "$backlight" ] || exit 0
[ -r "$max" ] || exit 0

value="$(cat "$max")"
printf '%s' "$value" >"$backlight"
