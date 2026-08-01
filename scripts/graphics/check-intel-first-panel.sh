#!/usr/bin/env bash
# check-intel-first-panel.sh — verify MacBookPro11,3 Intel-owned internal panel
#
# Safe, read-only checks. Run on Linux after an EFI-stub / UKI boot that has
# exercised Apple Set OS, with gpu-power-prefs already set to Intel from macOS.
#
# Exit codes:
#   0  all critical checks passed
#   1  one or more critical checks failed
#   2  usage / not Linux
#
# See docs/graphics/intel-first-repro.md

set -euo pipefail

critical_fail=0
warn_fail=0

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; critical_fail=1; }
warn() { printf 'WARN  %s\n' "$*"; warn_fail=1; }
info() { printf 'INFO  %s\n' "$*"; }

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This checker runs on Linux only." >&2
  exit 2
fi

echo "=== MacBookPro11,3 Intel-first panel check ==="
echo

# DMI (informational)
if [[ -r /sys/class/dmi/id/product_name ]]; then
  info "DMI product_name=$(tr -d '\0' </sys/class/dmi/id/product_name)"
fi

# PCI: Intel Iris / Crystal Well + NVIDIA Kepler Mac Edition
if lspci -nn 2>/dev/null | grep -qiE '8086:0d26'; then
  pass "Intel GPU 8086:0d26 enumerated"
else
  fail "Intel GPU 8086:0d26 not enumerated (Apple Set OS / EFI-stub path missing?)"
fi

if lspci -nn 2>/dev/null | grep -qiE '10de:0fe9'; then
  info "NVIDIA 10de:0fe9 present (expected on this model)"
else
  warn "NVIDIA 10de:0fe9 not seen (unusual for MacBookPro11,3)"
fi

# Framebuffer
fb_name=""
if [[ -r /sys/class/graphics/fb0/name ]]; then
  fb_name=$(tr -d '\0' </sys/class/graphics/fb0/name)
  info "fb0 name=${fb_name}"
fi
if [[ "${fb_name}" == *i915* ]]; then
  pass "Primary fb looks like i915 (${fb_name})"
else
  fail "Primary fb is not i915 (got '${fb_name:-none}') — panel likely not Intel-owned"
fi

# DRM connectors: look for enabled eDP
edp_ok=0
if [[ -d /sys/class/drm ]]; then
  for status in /sys/class/drm/card*-eDP-*/status; do
    [[ -e "$status" ]] || continue
    st=$(cat "$status" 2>/dev/null || true)
    conn=$(basename "$(dirname "$status")")
    info "connector ${conn} status=${st}"
    if [[ "$st" == "connected" ]]; then
      edp_ok=1
    fi
  done
fi
if [[ "$edp_ok" -eq 1 ]]; then
  pass "At least one eDP connector reports connected"
else
  fail "No connected eDP connector found under /sys/class/drm"
fi

# Preferred mode hint (2880x1800 on this Retina)
if command -v xrandr >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
  if xrandr 2>/dev/null | grep -qE '2880x1800'; then
    pass "xrandr sees 2880x1800"
  else
    warn "xrandr running but 2880x1800 not listed (Wayland-only session?)"
  fi
else
  info "Skipping xrandr mode check (no DISPLAY or no xrandr)"
fi

# switcheroo
switch_path=/sys/kernel/debug/vgaswitcheroo/switch
if [[ -r "$switch_path" ]] || [[ -r /sys/kernel/debug/vgaswitcheroo/switch ]]; then
  # may need root
  sw=$(cat /sys/kernel/debug/vgaswitcheroo/switch 2>/dev/null || true)
  if [[ -z "$sw" ]]; then
    sw=$(sudo cat /sys/kernel/debug/vgaswitcheroo/switch 2>/dev/null || true)
  fi
  if [[ -n "$sw" ]]; then
    info "vgaswitcheroo:"
    printf '%s\n' "$sw" | sed 's/^/      /'
    if printf '%s\n' "$sw" | grep -qE 'IGD:\+:Pwr'; then
      pass "IGD is selected and powered"
    else
      warn "IGD not clearly +/Pwr — inspect switcheroo dump"
    fi
    if printf '%s\n' "$sw" | grep -qE 'DIS:.*Off'; then
      pass "DIS reports Off (cooler idle profile)"
    elif printf '%s\n' "$sw" | grep -qE 'DIS:.*Pwr'; then
      warn "DIS still powered — consider: echo OFF | sudo tee /sys/kernel/debug/vgaswitcheroo/switch"
    fi
  else
    warn "Could not read vgaswitcheroo (need root / debugfs?)"
  fi
else
  warn "vgaswitcheroo debugfs not available"
fi

# Modules
if lsmod | grep -q '^i915 '; then
  pass "i915 module loaded"
else
  fail "i915 module not loaded"
fi

echo
if [[ "$critical_fail" -eq 0 ]]; then
  echo "RESULT: critical checks passed${warn_fail:+ (with warnings)}"
  exit 0
fi
echo "RESULT: critical checks FAILED"
echo "See docs/graphics/intel-first-repro.md"
exit 1
