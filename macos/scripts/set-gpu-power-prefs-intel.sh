#!/bin/bash
# set-gpu-power-prefs-intel.sh — run in macOS Terminal (Big Sur and similar)
#
# Sets Apple gpu-power-prefs to prefer the Intel iGPU so a subsequent Linux
# EFI-stub boot can own the internal Retina panel. Linux cannot reliably write
# this variable on this hardware; macOS is the supported writer.
#
# Discrete (macOS-oriented) value would be: %00%00%00%00
# Intel (Linux panel lab) value:           %01%00%00%00
#
# Requires admin privileges (sudo). Reboot into the Linux UKI/EFI-stub entry
# afterward. See docs/graphics/intel-first-repro.md

set -euo pipefail

GUID="fa4ce28d-b62f-4c99-9cc3-6815686e30f9"
KEY="${GUID}:gpu-power-prefs"
INTEL="%01%00%00%00"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Run this script on macOS, not Linux." >&2
  exit 2
fi

echo "Current gpu-related nvram (if any):"
nvram -p 2>/dev/null | grep -i gpu || true
echo
echo "Setting ${KEY} -> ${INTEL}"
sudo nvram "${KEY}=${INTEL}"
echo "Readback:"
sudo nvram "${KEY}"
echo
echo "Done. Reboot and select the Linux EFI-stub / UKI boot entry (Apple Set OS)."
echo "Then on Linux run: scripts/graphics/check-intel-first-panel.sh"
