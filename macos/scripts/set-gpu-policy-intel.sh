#!/bin/bash
# set-gpu-policy-intel.sh — run in macOS Terminal (Big Sur and similar)
#
# Sets gpu-policy to %01 (Intel). On this MacBookPro11,3 lab this variable
# survives macOS reboots and Linux sessions better than gpu-power-prefs.
# Pair with set-gpu-power-prefs-intel.sh and a UKI / EFI-stub Linux boot.
#
# See docs/graphics/intel-first-repro.md

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Run this script on macOS, not Linux." >&2
  exit 2
fi

echo "Current gpu-related nvram (if any):"
nvram -p 2>/dev/null | grep -i gpu || true
echo
echo "Setting gpu-policy -> %01"
sudo nvram gpu-policy=%01
echo "Readback:"
sudo nvram gpu-policy
echo
echo "Done. Also run set-gpu-power-prefs-intel.sh, then cold power-off and boot Linux via UKI."
