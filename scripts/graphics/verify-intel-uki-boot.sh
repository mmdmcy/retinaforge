#!/usr/bin/env bash
# verify-intel-uki-boot.sh — read-only checks for Intel-first UKI boots.
#
# Exit 0 when critical Intel-panel checks pass; 1 on failure; 2 on usage error.
# See docs/graphics/intel-first-repro.md

set -euo pipefail

critical_fail=0
warn_fail=0

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; critical_fail=1; }
warn() { printf 'WARN  %s\n' "$*"; warn_fail=1; }
info() { printf 'INFO  %s\n' "$*"; }

if [[ "$(uname -s)" != "Linux" ]]; then
	echo "Linux only." >&2
	exit 2
fi

echo "=== RetinaForge Intel UKI boot verification ==="
echo

if [[ -r /sys/devices/virtual/dmi/id/product_name ]]; then
	info "DMI product_name=$(tr -d '\0' </sys/devices/virtual/dmi/id/product_name)"
fi

if ls /sys/firmware/efi/efivars/StubInfo-* >/dev/null 2>&1; then
	pass "StubInfo EFI variable present (EFI-stub / UKI path)"
else
	fail "StubInfo missing — likely not an EFI-stub / UKI boot"
fi

if grep -qE 'blacklist=nvidia|modprobe\.blacklist=nvidia' /proc/cmdline 2>/dev/null; then
	warn "cmdline still carries nvidia blacklist params (OK if UKI predates rebuild)"
else
	info "cmdline has no nvidia blacklist tokens (expected after nvidia-off UKI rebuild)"
fi

for mod in nvidia nvidia_drm nvidia_modeset nvidia_uvm; do
	if lsmod | grep -q "^${mod} "; then
		fail "module loaded: ${mod}"
	else
		pass "module absent: ${mod}"
	fi
done

if lsmod | grep -q '^nouveau '; then
	info "nouveau loaded (expected for indexed GMUX switcheroo)"
else
	warn "nouveau not loaded (indexed GMUX may lack eDP modes)"
fi

if [[ -f /etc/modprobe.d/retinaforge-nvidia-off.conf ]]; then
	if systemctl is-failed --quiet retinaforge-nouveau.service 2>/dev/null; then
		fail "retinaforge-nouveau.service failed (conflicts with nvidia-off)"
	elif systemctl is-active --quiet retinaforge-nouveau.service 2>/dev/null; then
		fail "retinaforge-nouveau.service active while nvidia-off enabled"
	else
		pass "retinaforge-nouveau.service skipped (nvidia-off active)"
	fi
fi

if lspci -nn 2>/dev/null | grep -qiE '8086:0d26'; then
	pass "Intel GPU 8086:0d26 enumerated"
else
	fail "Intel GPU 8086:0d26 missing"
fi

if lsmod | grep -q '^i915 '; then
	pass "i915 loaded"
else
	fail "i915 not loaded"
fi

policy_var="$(ls /sys/firmware/efi/efivars/gpu-policy-* 2>/dev/null | head -1 || true)"
if [[ -n "$policy_var" && -r "$policy_var" ]]; then
	policy_data="$(python3 - "$policy_var" <<'PY'
import sys
b=open(sys.argv[1],'rb').read()
print(b[4:].hex() if len(b)>4 else 'empty')
PY
)"
	info "gpu-policy data=${policy_data}"
	[[ "$policy_data" == "01" ]] && pass "gpu-policy Intel (%01)" || warn "gpu-policy not %01"
else
	warn "gpu-policy efivar unreadable"
fi

prefs_var="$(ls /sys/firmware/efi/efivars/gpu-power-prefs-* 2>/dev/null | head -1 || true)"
if [[ -n "$prefs_var" ]]; then
	if prefs_size="$(stat -c%s "$prefs_var" 2>/dev/null)"; then
		case "$prefs_size" in
		4) warn "gpu-power-prefs size=4 (malformed / attributes-only?)" ;;
		8) info "gpu-power-prefs size=8 (staged for next boot or unread)" ;;
		*) info "gpu-power-prefs size=${prefs_size}" ;;
		esac
	fi
else
	info "gpu-power-prefs absent (may mean firmware consumed it — OK if panel on Intel)"
fi

fb_name=""
if [[ -r /sys/class/graphics/fb0/name ]]; then
	fb_name=$(tr -d '\0' </sys/class/graphics/fb0/name)
	info "fb0=${fb_name}"
fi
if [[ "$fb_name" == *i915* ]]; then
	pass "primary framebuffer is i915"
else
	fail "primary framebuffer is not i915 (got '${fb_name:-none}')"
fi

intel_edp=0
for card in /sys/class/drm/card*; do
	[[ -d "$card/device/driver" ]] || continue
	driver="$(readlink -f "$card/device/driver" | xargs basename)"
	[[ "$driver" == "i915" ]] || continue
	for status in "$card"-eDP-*/status; do
		[[ -e "$status" ]] || continue
		conn=$(basename "$(dirname "$status")")
		st=$(cat "$status")
		info "i915 ${conn} status=${st}"
		[[ "$st" == "connected" ]] && intel_edp=1
	done
done
if [[ "$intel_edp" -eq 1 ]]; then
	pass "i915 owns a connected eDP connector"
else
	fail "no connected eDP on i915"
fi

switch_path=/sys/kernel/debug/vgaswitcheroo/switch
if sw=$(cat "$switch_path" 2>/dev/null || sudo cat "$switch_path" 2>/dev/null || true); then
	if [[ -n "$sw" ]]; then
		info "vgaswitcheroo:"
		printf '%s\n' "$sw" | sed 's/^/      /'
		if printf '%s\n' "$sw" | grep -qE 'IGD:\+:Pwr'; then
			pass "IGD selected and powered"
		else
			warn "IGD not clearly +/Pwr"
		fi
	else
		warn "vgaswitcheroo unavailable"
	fi
else
	warn "vgaswitcheroo unavailable"
fi

echo
if [[ "$critical_fail" -eq 0 ]]; then
	echo "RESULT: critical checks passed${warn_fail:+ (with warnings)}"
	exit 0
fi
echo "RESULT: critical checks FAILED"
exit 1
