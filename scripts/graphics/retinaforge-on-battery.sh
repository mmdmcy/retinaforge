#!/usr/bin/env bash
# udev: AC unplugged. Re-apply desk policy unless COMMUTE_SLEEP=1.
set -euo pipefail
exec /usr/local/sbin/retinaforge-power-policy.sh apply
