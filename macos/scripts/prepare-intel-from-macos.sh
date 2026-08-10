#!/bin/bash
# prepare-intel-from-macos.sh — set GPU NVRAM for Intel-first Linux UKI boot
#
# Run in macOS Terminal on the MacBook Pro 11,3 lab machine, then cold
# power-off (shutdown -h now), power on, and select the Limine UKI /
# "Intel probe" entry.
#
# See docs/graphics/intel-first-repro.md

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Run on macOS." >&2
  exit 2
fi

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

echo "=== gpu-policy ==="
"$root/macos/scripts/set-gpu-policy-intel.sh"
echo
echo "=== gpu-power-prefs ==="
"$root/macos/scripts/set-gpu-power-prefs-intel.sh"
echo
echo "=== done ==="
echo "Next:"
echo "  1. sudo shutdown -h now    # cold off, not reboot"
echo "  2. Power on → Limine → pick the UKI / Intel probe entry"
echo "  3. On Linux: sudo $root/scripts/graphics/check-intel-first-panel.sh"
