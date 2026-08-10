#!/bin/sh
# Log Apple gpu-policy / gpu-power-prefs for mux diagnostics.
set -eu
tag=retinaforge-gpu-nvram
for var in /sys/firmware/efi/efivars/gpu-policy-* /sys/firmware/efi/efivars/gpu-power-prefs-*; do
	[ -r "$var" ] || continue
	hex=$(od -An -tx1 -N16 "$var" 2>/dev/null | tr -d ' \n' || true)
	logger -t "$tag" "$(basename "$var")=${hex}"
done
cmdline=$(tr '\0' ' ' </proc/cmdline)
logger -t "$tag" "cmdline=${cmdline}"
if [ -d /sys/module/i915 ]; then
	logger -t "$tag" "i915=$(dmesg 2>/dev/null | grep -iE 'link info|edp' | tail -3 | tr '\n' ' ')"
fi
