#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
checker=$repo_root/scripts/initramfs/check-storage-trace.awk

command -v busybox >/dev/null 2>&1 || {
	printf 'error: busybox is required\n' >&2
	exit 1
}

busybox awk -f "$checker" <<'EOF'
worker-1 [000] d..1. 1.000000: ata_qc_issue: ata_port=1 ata_dev=0 tag=4 proto=ATA_PROT_NODATA cmd=ATA_CMD_FLUSH_EXT
idle-0 [001] d.h2. 1.100000: ata_qc_complete_done: ata_port=1 ata_dev=0 tag=4 flags=9
EOF

if busybox awk -f "$checker" >/dev/null 2>&1 <<'EOF'
worker-1 [000] d..1. 1.000000: ata_qc_issue: ata_port=1 ata_dev=0 tag=4 proto=ATA_PROT_NODATA cmd=ATA_CMD_FLUSH_EXT
idle-0 [001] d.h2. 1.100000: ata_qc_complete_failed: ata_port=1 ata_dev=0 tag=4 flags=9
EOF
then
	printf 'error: failed ATA flush was accepted\n' >&2
	exit 1
fi

if busybox awk -f "$checker" >/dev/null 2>&1 <<'EOF'
worker-1 [000] d..1. 1.000000: ata_qc_issue: ata_port=1 ata_dev=0 tag=4 proto=ATA_PROT_NODATA cmd=ATA_CMD_FLUSH_EXT
worker-1 [000] d..1. 1.010000: ata_qc_issue: ata_port=1 ata_dev=0 tag=4 proto=ATA_PROT_DMA cmd=ATA_CMD_READ_EXT
idle-0 [001] d.h2. 1.100000: ata_qc_complete_done: ata_port=1 ata_dev=0 tag=4 flags=9
EOF
then
	printf 'error: duplicate ATA tag was accepted\n' >&2
	exit 1
fi

printf 'BusyBox ATA trace acceptance QA passed.\n'
