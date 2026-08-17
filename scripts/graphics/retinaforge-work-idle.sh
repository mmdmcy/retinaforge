#!/usr/bin/env bash
# Manual: sleep unused GT 750M (Intel lid only). Prefer the tray plate.
# Automatic policy keeps the 750M on (desk / no commute use).
set -euo pipefail
policy=/usr/local/sbin/retinaforge-power-policy.sh
if [[ ! -x $policy ]]; then
	policy="$(CDPATH= cd -- "$(dirname "$0")" && pwd)/retinaforge-power-policy.sh"
fi
exec "$policy" commute
