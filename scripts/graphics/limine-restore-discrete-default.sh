#!/usr/bin/env bash
# limine-restore-discrete-default.sh — emergency SSH recovery menu default only.

set -euo pipefail

limine_conf=/boot/limine.conf

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

cp -a "$limine_conf" "${limine_conf}.bak-before-discrete-default-$(date +%Y%m%d-%H%M%S)"
sed -i 's/^default_entry:.*/default_entry: 1/' "$limine_conf"
sed -i 's/^timeout:.*/timeout: 8/' "$limine_conf"
echo "limine default_entry=1 (linux-cachyos-lts under /+CachyOS)"
