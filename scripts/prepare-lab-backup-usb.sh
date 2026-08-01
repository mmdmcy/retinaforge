#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Prepare the one removable medium as a Linux lab volume plus APFS backup space.
set -euo pipefail

device=
confirmation=
expected_size_bytes=126877696000

usage() {
	cat <<'EOF'
Usage: prepare-lab-backup-usb.sh --device /dev/sdX [--confirm TOKEN]

The first invocation validates without writing and prints the exact destructive
confirmation token. The selected USB is erased and receives:
  1. 1 GiB FAT32, GPT/volume name MBP_AHCI
  2. remaining space, GPT name MBP_BACKUP and Apple APFS type (unformatted)
EOF
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

while (($#)); do
	case "$1" in
		--device)
			device=${2:?missing value after --device}
			shift 2
			;;
		--confirm)
			confirmation=${2:?missing value after --confirm}
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*) die "unknown argument: $1" ;;
	esac
done

[[ -n $device ]] || {
	usage >&2
	exit 2
}
for command in basename blkid blockdev cat cut findmnt fsck.vfat grep lsblk \
	mkfs.vfat partprobe readlink sgdisk sha256sum swapon tr udevadm wipefs; do
	command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

[[ -b $device ]] || die "not a block device: $device"
device=$(readlink -f "$device")
name=$(basename "$device")
[[ $name =~ ^sd[b-z]$ ]] || \
	die 'only removable /dev/sd[b-z] whole-disk devices are accepted'
[[ $device != /dev/sda ]] || die 'the Linux system disk is permanently refused'
[[ -r /sys/class/block/$name/removable ]] || die 'missing removable-device metadata'
[[ $(</sys/class/block/$name/removable) == 1 ]] || die "$device is not marked removable"

transport=$(lsblk -dn -o TRAN "$device" | tr -d '[:space:]')
[[ $transport == usb ]] || die "$device transport is '$transport', not USB"
size_bytes=$(lsblk -dnb -o SIZE "$device" | tr -d '[:space:]')
[[ $size_bytes =~ ^[0-9]+$ ]] || die 'could not determine device size'
[[ $size_bytes == "$expected_size_bytes" ]] || \
	die "USB size is $size_bytes bytes, expected the approved $expected_size_bytes-byte medium"

while IFS= read -r node; do
	[[ -n $node ]] || continue
	if findmnt -rn -S "$node" >/dev/null 2>&1; then
		die "$node is mounted"
	fi
	if swapon --noheadings --raw --show=NAME 2>/dev/null | grep -Fxq "$node"; then
		die "$node is active swap"
	fi
done < <(lsblk -nrpo NAME "$device")

root_source=$(findmnt -n -o SOURCE /)
if lsblk -snrpo NAME "$root_source" 2>/dev/null | grep -Fxq "$device"; then
	die "$device backs the running root filesystem"
fi

current_partition="${device}1"
[[ -b $current_partition && ! -b ${device}2 ]] || \
	die 'approved archived layout must contain only partition 1'
current_name=$(basename "$current_partition")
grep -Fxq 'PARTNAME=MBP_IGPU' "/sys/class/block/$current_name/uevent" || \
	die 'current payload GPT name is not MBP_IGPU'
[[ $(lsblk -dn -o FSTYPE "$current_partition" | tr -d '[:space:]') == vfat ]] || \
	die 'current payload partition is not FAT'
[[ $(lsblk -dn -o LABEL "$current_partition" | tr -d '[:space:]') == MBP_IGPU ]] || \
	die 'current payload FAT label is not MBP_IGPU'
[[ $(cat "/sys/class/block/$current_name/start") == 2048 ]] || \
	die 'current payload start sector is unexpected'
[[ $(cat "/sys/class/block/$current_name/size") == 2097152 ]] || \
	die 'current payload size is not exactly 1 GiB'
current_fingerprint=$(
	{
		printf '%s\n' "$size_bytes"
		cat "/sys/class/block/$current_name/start"
		cat "/sys/class/block/$current_name/size"
		grep -E '^(PARTNAME|PARTUUID)=' "/sys/class/block/$current_name/uevent"
		lsblk -dn -o UUID "$current_partition" | tr -d '[:space:]'
	} | sha256sum | cut -d' ' -f1
)
token="ERASE-LAB-BACKUP:${device}:${size_bytes}:${current_fingerprint}"
printf 'Validated candidate USB; no writes performed.\n'
printf 'Approved payload fingerprint: %s\n' "$current_fingerprint"
lsblk -o NAME,PATH,TRAN,RM,SIZE,MODEL,FSTYPE,LABEL,MOUNTPOINTS "$device"
printf '\nExisting signatures:\n'
wipefs -n "$device" || true
if [[ -z $confirmation ]]; then
	printf '\nTo erase and repartition this exact device, rerun with:\n'
	printf '  --confirm %q\n' "$token"
	exit 2
fi
[[ $confirmation == "$token" ]] || \
	die 'confirmation token does not match this device and size'
((EUID == 0)) || die 'destructive invocation must run as root (use sudo)'

wipefs --all --force "$device"
sgdisk --zap-all "$device"
sgdisk --clear \
	--new=1:2048:+1024M \
	--typecode=1:ef00 \
	--change-name=1:MBP_AHCI \
	--new=2:0:0 \
	--typecode=2:af0a \
	--change-name=2:MBP_BACKUP \
	"$device"
partprobe "$device"
udevadm settle

lab_partition="${device}1"
backup_partition="${device}2"
[[ -b $lab_partition ]] || die "lab partition did not appear: $lab_partition"
[[ -b $backup_partition ]] || die "backup partition did not appear: $backup_partition"
mkfs.vfat -F 32 -n MBP_AHCI "$lab_partition"
wipefs --all --force "$backup_partition"
udevadm settle

sgdisk --verify "$device"
lab_name=$(basename "$lab_partition")
backup_name=$(basename "$backup_partition")
grep -Fxq 'PARTNAME=MBP_AHCI' "/sys/class/block/$lab_name/uevent" || \
	die 'lab GPT name verification failed'
[[ $(blkid -p -s PART_ENTRY_TYPE -o value "$lab_partition") == \
	c12a7328-f81f-11d2-ba4b-00a0c93ec93b ]] || die 'lab GPT type verification failed'
grep -Fxq 'PARTNAME=MBP_BACKUP' "/sys/class/block/$backup_name/uevent" || \
	die 'backup GPT name verification failed'
[[ $(blkid -p -s PART_ENTRY_TYPE -o value "$backup_partition") == \
	7c3457ef-0000-11aa-aa11-00306543ecac ]] || die 'backup GPT type verification failed'
[[ $(blkid -s LABEL -o value "$lab_partition") == MBP_AHCI ]] || \
	die 'lab FAT label verification failed'
[[ $(cat "/sys/class/block/$lab_name/start") == 2048 ]] || \
	die 'lab partition start sector verification failed'
[[ $(cat "/sys/class/block/$lab_name/size") == 2097152 ]] || \
	die 'lab partition size is not exactly 1 GiB'
disk_sectors=$(blockdev --getsz "$device")
backup_start=$(cat "/sys/class/block/$backup_name/start")
backup_sectors=$(cat "/sys/class/block/$backup_name/size")
	[[ $backup_start == 2099200 ]] || die 'backup partition start sector is unexpected'
# Accept classic GPT fill (disk-33) or Apple's 4 KiB-aligned APFS end (disk-40).
backup_end=$((backup_start + backup_sectors))
case "$backup_end" in
	"$((disk_sectors - 33))"|"$((disk_sectors - 40))") ;;
	*) die 'backup partition does not reach the final usable GPT sector' ;;
esac
[[ -z $(blkid -s TYPE -o value "$backup_partition" 2>/dev/null) ]] || \
	die 'backup partition unexpectedly retains a filesystem signature'
fsck.vfat -n "$lab_partition"
layout_fingerprint=$(
	{
		printf '%s\n' "$disk_sectors"
		for partition_name in "$lab_name" "$backup_name"; do
			cat "/sys/class/block/$partition_name/start"
			cat "/sys/class/block/$partition_name/size"
			grep -E '^(PARTNAME|PARTUUID)=' \
				"/sys/class/block/$partition_name/uevent"
		done
	} | sha256sum | cut -d' ' -f1
)

printf '\nDual-purpose USB is partitioned and unmounted.\n'
printf 'Device: %s\n' "$device"
printf 'Lab partition: %s (MBP_AHCI)\n' "$lab_partition"
printf 'Backup partition: %s (MBP_BACKUP; format as APFS on macOS)\n' "$backup_partition"
printf 'Private layout fingerprint: %s\n' "$layout_fingerprint"
