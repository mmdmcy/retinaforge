#!/usr/bin/env bash
# Collect controller state for an Apple AHCI investigation.
# The output is intended for local review. Serial numbers are redacted.
set -euo pipefail

controller="${1:-05:00.0}"
disk="${2:-/dev/sda}"

section() {
  printf '\n## %s\n' "$1"
}

section "kernel"
uname -a
cat /proc/cmdline

section "PCI controller"
lspci -nnk -s "$controller" || true

section "AHCI and queue settings"
for path in \
  /sys/class/scsi_host/host0/link_power_management_policy \
  /sys/block/sda/queue/scheduler \
  /sys/block/sda/queue/nr_requests \
  /sys/block/sda/queue/write_cache \
  /sys/module/pcie_aspm/parameters/policy; do
  if [[ -r "$path" ]]; then
    printf '%s: ' "$path"
    cat "$path"
  fi
done

section "kernel storage messages"
journalctl -k -b 0 --no-pager 2>/dev/null |
  grep -Ei 'ahci|ata[0-9]|jbd2|I/O error|timeout|reset|ext4' |
  tail -n 200 || true

section "SMART summary (serial redacted)"
if command -v smartctl >/dev/null 2>&1; then
  smartctl -a "$disk" 2>/dev/null |
    sed -E \
      -e 's/^(Serial Number:).*/\1 <redacted>/' \
      -e 's/^(LU WWN Device Id:).*/\1 <redacted>/'
fi
