#!/usr/bin/env bash
# udev: AC plugged. Wake the 750M (native HDMI/TB) and balanced — do not power-saver.
set -euo pipefail
exec /usr/local/sbin/retinaforge-power-policy.sh apply
