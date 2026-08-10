#!/bin/sh
# set-gpu-policy-intel.sh — prefer Intel iGPU at firmware power-on (Linux writer)
#
# On this MacBookPro11,3 + Big Sur lab, gpu-policy %01 is the variable that
# survives macOS reboots and Linux sessions. gpu-power-prefs is still best
# written from macOS (see macos/scripts/set-gpu-power-prefs-intel.sh).
#
# See docs/graphics/intel-first-repro.md

set -eu

ATTR="$(printf '\007\000\000\200')"
POLICY_VAR=/sys/firmware/efi/efivars/gpu-policy-7c436110-ab2a-4bbb-a880-fe41995c9f82
PREFS_VAR=/sys/firmware/efi/efivars/gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9
INTEL_PREFS="$(printf '\001\000\000\000')"

write_efivar() {
	path="$1"
	payload="$2"
	tmp="$(mktemp)"
	# shellcheck disable=SC2050
	printf '%s' "$ATTR" >"$tmp"
	printf '%s' "$payload" >>"$tmp"
	chattr -i "$path" 2>/dev/null || true
	cp "$tmp" "$path"
	chattr +i "$path" 2>/dev/null || true
	rm -f "$tmp"
}

if [ "$(id -u)" -ne 0 ]; then
	echo "run as root: sudo $0" >&2
	exit 1
fi

write_efivar "$POLICY_VAR" "$(printf '\001')"
if [ -e "$PREFS_VAR" ] || [ -w /sys/firmware/efi/efivars ]; then
	write_efivar "$PREFS_VAR" "$INTEL_PREFS" || echo "warn: gpu-power-prefs write failed; set from macOS if needed"
fi

echo "gpu-policy set to Intel (%01)"
if [ -r "$POLICY_VAR" ]; then
	python3 - "$POLICY_VAR" <<'PY'
import sys
b=open(sys.argv[1],'rb').read()
print('readback:', b.hex(), 'data=', b[4:] if len(b)>4 else b'')
PY
fi
