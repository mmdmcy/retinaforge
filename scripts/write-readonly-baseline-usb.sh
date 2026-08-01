#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Safely provision a removable USB with the read-only baseline EFI appliance.
set -euo pipefail

repo_root=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
artifact_root=${ARTIFACT_ROOT:-$repo_root/build/readonly-baseline-v7.1.3/artifact}
artifact_profile=readonly-baseline
preserve_backup=0
nodes_hidden=0
device=
confirmation=

usage() {
	cat <<'EOF'
Usage: write-readonly-baseline-usb.sh --device /dev/sdX
       [--artifact-root DIR] [--profile readonly-baseline|legacy-stack|flush-reg-stack|plain-heavy-stack]
       [--preserve-backup] [--confirm TOKEN]

The first invocation without --confirm performs only validation and prints the
exact token required for the destructive invocation. The entire selected USB
is erased unless --preserve-backup validates the two-partition lab/backup
layout. The script never auto-selects a device.
EOF
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

while (($#)); do
	case "$1" in
		--artifact-root)
			artifact_root=${2:?missing value after --artifact-root}
			shift 2
			;;
		--device)
			device=${2:?missing value after --device}
			shift 2
			;;
		--profile)
			artifact_profile=${2:?missing value after --profile}
			shift 2
			;;
		--preserve-backup)
			preserve_backup=1
			shift
			;;
		--confirm)
			confirmation=${2:?missing value after --confirm}
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			die "unknown argument: $1"
			;;
	esac
done

[[ -n $device ]] || {
	usage >&2
	exit 2
}
for command in awk basename blkid blockdev cat cut dd findmnt fsck.vfat grep install \
	lsblk mkdir mkfs.vfat mknod mount partprobe readlink rm rmdir sgdisk \
	sha256sum swapon sync tr udevadm umount wc wipefs; do
	command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[[ -b $device ]] || die "not a block device: $device"
device=$(readlink -f "$device")
name=$(basename "$device")
[[ $name =~ ^sd[b-z]$ ]] || \
	die "only removable /dev/sd[b-z] whole-disk devices are accepted"
[[ $device != /dev/sda ]] || die "refusing to write the build host system disk (/dev/sda)"
[[ -r /sys/class/block/$name/removable ]] || die "missing removable-device metadata"
[[ $(</sys/class/block/$name/removable) == 1 ]] || die "$device is not marked removable"

transport=$(lsblk -dn -o TRAN "$device" | tr -d '[:space:]')
[[ $transport == usb ]] || die "$device transport is '$transport', not USB"

size_bytes=$(lsblk -dnb -o SIZE "$device" | tr -d '[:space:]')
[[ $size_bytes =~ ^[0-9]+$ ]] || die "could not determine device size"
((size_bytes >= 4 * 1024 * 1024 * 1024)) || die "USB is smaller than 4 GiB"
((size_bytes <= 256 * 1024 * 1024 * 1024)) || die "USB is larger than the 256 GiB safety limit"

while IFS= read -r node; do
	[[ -n $node ]] || continue
	if findmnt -rn -S "$node" >/dev/null 2>&1; then
		die "$node is mounted; unmount it before continuing"
	fi
	if swapon --noheadings --raw --show=NAME 2>/dev/null | grep -Fxq "$node"; then
		die "$node is active swap"
	fi
done < <(lsblk -nrpo NAME "$device")

root_source=$(findmnt -n -o SOURCE /)
if lsblk -snrpo NAME "$root_source" 2>/dev/null | grep -Fxq "$device"; then
	die "$device backs the running root filesystem"
fi

backup_layout_detected=0
[[ -b ${device}2 ]] && backup_layout_detected=1
if ((backup_layout_detected && !preserve_backup)); then
	die 'MBP_BACKUP is present; refusing any whole-disk erase without --preserve-backup'
fi

if ((preserve_backup)); then
	[[ $size_bytes == 126877696000 ]] || \
		die 'preserved layout is not on the approved 126877696000-byte medium'
	lab_partition="${device}1"
	backup_partition="${device}2"
	[[ -b $lab_partition && -b $backup_partition ]] || \
		die 'the preserved layout does not contain partitions 1 and 2'
	partition_count=$(lsblk -nrpo NAME "$device" | wc -l)
	[[ $partition_count -eq 3 ]] || \
		die 'the preserved layout must contain exactly two partitions'
	lab_name=$(basename "$lab_partition")
	backup_name=$(basename "$backup_partition")
	grep -Fxq 'PARTNAME=MBP_AHCI' "/sys/class/block/$lab_name/uevent" || \
		die 'partition 1 GPT name is not MBP_AHCI'
	[[ $(lsblk -dn -o PARTTYPE "$lab_partition" | tr -d '[:space:]') == \
		c12a7328-f81f-11d2-ba4b-00a0c93ec93b ]] || \
		die 'partition 1 is not EFI-system type'
	grep -Fxq 'PARTNAME=MBP_BACKUP' "/sys/class/block/$backup_name/uevent" || \
		die 'partition 2 GPT name is not MBP_BACKUP'
	[[ $(lsblk -dn -o PARTTYPE "$backup_partition" | tr -d '[:space:]') == \
		7c3457ef-0000-11aa-aa11-00306543ecac ]] || \
		die 'partition 2 is not Apple APFS type'
	[[ $(lsblk -dn -o FSTYPE "$lab_partition" | tr -d '[:space:]') == vfat ]] || \
		die 'partition 1 is not FAT'
	[[ $(lsblk -dn -o LABEL "$lab_partition" | tr -d '[:space:]') == MBP_AHCI ]] || \
		die 'partition 1 FAT label is not MBP_AHCI'
	# Partition 2 is identified by GPT type/name/geometry/PARTUUID. Do not
	# require Linux blkid FSTYPE=apfs: some hosts mis-probe or unstably read
	# Apple APFS containers over USB even when the GPT type is correct.
	lab_start=$(cat "/sys/class/block/$lab_name/start")
	lab_sectors=$(cat "/sys/class/block/$lab_name/size")
	backup_start=$(cat "/sys/class/block/$backup_name/start")
	backup_sectors=$(cat "/sys/class/block/$backup_name/size")
	disk_sectors=$(blockdev --getsz "$device")
	[[ $lab_start == 2048 && $lab_sectors == 2097152 ]] || \
		die 'partition 1 is not the approved 1 GiB geometry'
	[[ $backup_start == 2099200 && $backup_sectors == 245708760 ]] || \
		die 'partition 2 is not the approved 4 KiB-aligned geometry'
	lab_partuuid=$(awk -F= '$1 == "PARTUUID" { print tolower($2) }' \
		"/sys/class/block/$lab_name/uevent")
	backup_partuuid=$(awk -F= '$1 == "PARTUUID" { print tolower($2) }' \
		"/sys/class/block/$backup_name/uevent")
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
fi

bootloader_image=$artifact_root/EFI/BOOT/BOOTX64.EFI
kernel_image=$artifact_root/lab/vmlinuz
kernel_config=$artifact_root/lab/kernel.config
[[ -f $bootloader_image ]] || die "baseline EFI bootloader not found: $bootloader_image"
[[ -f $kernel_image ]] || die "baseline kernel not found: $kernel_image"
[[ -f $kernel_config ]] || die "baseline kernel config not found: $kernel_config"
(
	cd "$artifact_root"
	sha256sum -c SHA256SUMS
) || die "artifact checksum verification failed"

grep -Fxq 'CONFIG_CMDLINE_OVERRIDE=y' "$kernel_config" || \
	die 'artifact does not enforce its built-in kernel command line'
cmdline_setting=$(grep -E '^CONFIG_CMDLINE=".*"$' "$kernel_config" || true)
[[ -n $cmdline_setting ]] || die 'artifact kernel command line is unavailable'
kernel_cmdline=${cmdline_setting#CONFIG_CMDLINE=\"}
kernel_cmdline=${kernel_cmdline%\"}
require_cmdline_token() {
	case " $kernel_cmdline " in
		*" $1 "*) ;;
		*) die "artifact command line is missing required token: $1" ;;
	esac
}
reject_cmdline_token() {
	case " $kernel_cmdline " in
		*" $1 "*) die "artifact command line contains forbidden token: $1" ;;
	esac
}
require_numeric_cmdline_setting() {
	local prefix=$1
	local argument
	local count=0
	local value
	for argument in $kernel_cmdline; do
		case "$argument" in
			"$prefix"=*)
				value=${argument#*=}
				[[ $value =~ ^(0|[1-9][0-9]*)$ ]] || \
					die "artifact geometry is not canonical numeric data: $prefix"
				count=$((count + 1))
				;;
		esac
	done
	[[ $count -eq 1 ]] || \
		die "artifact command line does not contain one geometry value: $prefix"
}
require_uuid_cmdline_setting() {
	local prefix=$1
	local argument
	local count=0
	local value
	for argument in $kernel_cmdline; do
		case "$argument" in
			"$prefix"=*)
				value=${argument#*=}
				[[ $value =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || \
					die "artifact partition identity is invalid: $prefix"
				count=$((count + 1))
				;;
		esac
	done
	[[ $count -eq 1 ]] || \
		die "artifact command line does not contain one partition identity: $prefix"
}
cmdline_value() {
	local prefix=$1
	local argument
	local count=0
	local value=
	for argument in $kernel_cmdline; do
		case "$argument" in
			"$prefix"=*)
				value=${argument#*=}
				count=$((count + 1))
				;;
		esac
	done
	[[ $count -eq 1 ]] || die "artifact does not contain one value for $prefix"
	printf '%s\n' "$value"
}

case "$artifact_profile" in
	readonly-baseline)
		grep -Fxq 'CONFIG_LOCALVERSION="-mbp-ahci-baseline"' "$kernel_config" || \
			die 'artifact is not the stock read-only baseline profile'
		reject_cmdline_token 'mbp_ahci.write_test=1'
		reject_cmdline_token 'ahci.mbp11_3_msi_diagnostic=1'
		;;
	legacy-stack)
		((preserve_backup)) || \
			die 'legacy-stack provisioning requires --preserve-backup'
		grep -Fxq 'CONFIG_LOCALVERSION="-mbp-ahci-legacy-stack"' "$kernel_config" || \
			die 'artifact is not the stock legacy-stack profile'
		for token in \
			mbp_ahci.write_test=1 \
			mbp_ahci.stack_test=1; do
			require_cmdline_token "$token"
		done
		for prefix in \
			mbp_ahci.scratch_partition \
			mbp_ahci.partition_count \
			mbp_ahci.scratch_start \
			mbp_ahci.scratch_sectors \
			mbp_ahci.target_sectors; do
			require_numeric_cmdline_setting "$prefix"
		done
		require_numeric_cmdline_setting mbp_ahci.capture_disk_sectors
		require_uuid_cmdline_setting mbp_ahci.capture_lab_partuuid
		require_uuid_cmdline_setting mbp_ahci.capture_backup_partuuid
		[[ $(cmdline_value mbp_ahci.capture_disk_sectors) == "$disk_sectors" ]] || \
			die 'artifact capture disk size does not match this USB'
		[[ $(cmdline_value mbp_ahci.capture_lab_partuuid) == "$lab_partuuid" ]] || \
			die 'artifact capture lab UUID does not match this USB'
		[[ $(cmdline_value mbp_ahci.capture_backup_partuuid) == "$backup_partuuid" ]] || \
			die 'artifact capture backup UUID does not match this USB'
		reject_cmdline_token 'ahci.mbp11_3_msi_diagnostic=1'
		reject_cmdline_token 'libata.force=noncq'
		reject_cmdline_token 'libahci.mbp11_3_flush_reg_sample=1'
		;;
	flush-reg-stack)
		((preserve_backup)) || \
			die 'flush-reg-stack provisioning requires --preserve-backup'
		grep -Fxq 'CONFIG_LOCALVERSION="-mbp-ahci-flush-reg-stack"' "$kernel_config" || \
			die 'artifact is not the flush-reg-stack profile'
		for token in \
			mbp_ahci.write_test=1 \
			mbp_ahci.stack_test=1 \
			libahci.mbp11_3_flush_reg_sample=1; do
			require_cmdline_token "$token"
		done
		for prefix in \
			mbp_ahci.scratch_partition \
			mbp_ahci.partition_count \
			mbp_ahci.scratch_start \
			mbp_ahci.scratch_sectors \
			mbp_ahci.target_sectors; do
			require_numeric_cmdline_setting "$prefix"
		done
		require_numeric_cmdline_setting mbp_ahci.capture_disk_sectors
		require_uuid_cmdline_setting mbp_ahci.capture_lab_partuuid
		require_uuid_cmdline_setting mbp_ahci.capture_backup_partuuid
		[[ $(cmdline_value mbp_ahci.capture_disk_sectors) == "$disk_sectors" ]] || \
			die 'artifact capture disk size does not match this USB'
		[[ $(cmdline_value mbp_ahci.capture_lab_partuuid) == "$lab_partuuid" ]] || \
			die 'artifact capture lab UUID does not match this USB'
		[[ $(cmdline_value mbp_ahci.capture_backup_partuuid) == "$backup_partuuid" ]] || \
			die 'artifact capture backup UUID does not match this USB'
		reject_cmdline_token 'ahci.mbp11_3_msi_diagnostic=1'
		reject_cmdline_token 'libata.force=noncq'
		;;
	plain-heavy-stack)
		((preserve_backup)) || \
			die 'plain-heavy-stack provisioning requires --preserve-backup'
		grep -Fxq 'CONFIG_LOCALVERSION="-mbp-ahci-plain-heavy-stack"' "$kernel_config" || \
			die 'artifact is not the plain-heavy-stack profile'
		for token in \
			mbp_ahci.write_test=1 \
			mbp_ahci.stack_test=1 \
			libahci.mbp11_3_flush_reg_sample=1; do
			require_cmdline_token "$token"
		done
		for prefix in \
			mbp_ahci.scratch_partition \
			mbp_ahci.partition_count \
			mbp_ahci.scratch_start \
			mbp_ahci.scratch_sectors \
			mbp_ahci.target_sectors; do
			require_numeric_cmdline_setting "$prefix"
		done
		require_numeric_cmdline_setting mbp_ahci.capture_disk_sectors
		require_uuid_cmdline_setting mbp_ahci.capture_lab_partuuid
		require_uuid_cmdline_setting mbp_ahci.capture_backup_partuuid
		[[ $(cmdline_value mbp_ahci.capture_disk_sectors) == "$disk_sectors" ]] || \
			die 'artifact capture disk size does not match this USB'
		[[ $(cmdline_value mbp_ahci.capture_lab_partuuid) == "$lab_partuuid" ]] || \
			die 'artifact capture lab UUID does not match this USB'
		[[ $(cmdline_value mbp_ahci.capture_backup_partuuid) == "$backup_partuuid" ]] || \
			die 'artifact capture backup UUID does not match this USB'
		reject_cmdline_token 'ahci.mbp11_3_msi_diagnostic=1'
		reject_cmdline_token 'libata.force=noncq'
		;;
	*) die "unsupported artifact profile: $artifact_profile" ;;
esac

bootloader_hash=$(sha256sum "$bootloader_image" | cut -d' ' -f1)
kernel_hash=$(sha256sum "$kernel_image" | cut -d' ' -f1)
manifest_hash=$(sha256sum "$artifact_root/SHA256SUMS" | cut -d' ' -f1)
token="WRITE:${device}:${size_bytes}:${artifact_profile}:${preserve_backup}:${kernel_hash}:${manifest_hash}:${layout_fingerprint:-none}"
printf 'Validated candidate USB (no writes performed):\n'
printf 'Artifact profile: %s\n' "$artifact_profile"
printf 'Kernel SHA-256: %s\n' "$kernel_hash"
printf 'Manifest SHA-256: %s\n' "$manifest_hash"
lsblk -o NAME,PATH,TRAN,RM,SIZE,MODEL,FSTYPE,LABEL,MOUNTPOINTS "$device"
printf '\nExisting signatures (still untouched):\n'
wipefs -n "$device" || true

if [[ -z $confirmation ]]; then
	printf '\nTo perform this exact USB write, rerun with:\n'
	printf '  --confirm %q\n' "$token"
	exit 2
fi
[[ $confirmation == "$token" ]] || \
	die "confirmation token does not match this device, artifact profile, and manifest"
((EUID == 0)) || die "destructive invocation must run as root (use sudo)"
if ((preserve_backup)); then
	blockdev --setro "$backup_partition" || die 'could not protect backup partition'
	[[ $(blockdev --getro "$backup_partition") == 1 ]] || \
		die 'backup partition did not become read-only'
fi

mount_dir=$(mktemp -d /tmp/mbp-ahci-usb.XXXXXX)
mounted=0
restore_hidden_nodes() {
	((nodes_hidden)) || return 0
	for node_data in \
		"$device:/sys/class/block/$name/dev" \
		"$backup_partition:/sys/class/block/$backup_name/dev"; do
		node_path=${node_data%%:*}
		dev_path=${node_data#*:}
		dev_numbers=$(cat "$dev_path") || return 1
		major=${dev_numbers%%:*}
		minor=${dev_numbers#*:}
		[[ -e $node_path ]] || mknod -m 0600 "$node_path" b "$major" "$minor" || return 1
	done
	blockdev --setro "$backup_partition" || return 1
	[[ $(blockdev --getro "$backup_partition") == 1 ]] || return 1
	nodes_hidden=0
}
cleanup() {
	local rc=$?
	trap - EXIT INT TERM
	if ((mounted)); then
		umount "$mount_dir" 2>/dev/null || true
	fi
	restore_hidden_nodes 2>/dev/null || true
	rmdir "$mount_dir" 2>/dev/null || true
	exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if ((preserve_backup)); then
	printf '\nUpdating only validated lab partition %s; backup partition remains read-only ...\n' \
		"$lab_partition"
	partition=$lab_partition
else
	printf '\nErasing validated removable USB %s ...\n' "$device"
	wipefs --all --force "$device"
	sgdisk --zap-all "$device"
	sgdisk --clear \
		--new=1:2048:+1024M \
		--typecode=1:ef00 \
		--change-name=1:MBP_AHCI \
		"$device"
	partprobe "$device"
	udevadm settle
	partition="${device}1"
	[[ -b $partition ]] || die "expected partition did not appear: $partition"
	mkfs.vfat -F 32 -n MBP_AHCI "$partition"
fi

mount -t vfat -o rw,noatime "$partition" "$mount_dir"
mounted=1
if ((preserve_backup)); then
	nodes_hidden=1
	rm -f "$device" "$backup_partition"
	[[ ! -e $device && ! -e $backup_partition ]] || \
		die 'could not hide whole-disk and backup device nodes'
	rm -rf -- \
		"$mount_dir/EFI" \
		"$mount_dir/lab" \
		"$mount_dir/captures" \
		"$mount_dir/failures"
fi
install -D -m 0644 "$bootloader_image" "$mount_dir/EFI/BOOT/BOOTX64.EFI"
install -D -m 0644 "$kernel_image" "$mount_dir/lab/vmlinuz"
install -D -m 0644 "$artifact_root/lab/grub.cfg" "$mount_dir/lab/grub.cfg"
install -D -m 0644 "$artifact_root/lab/kernel.config" "$mount_dir/lab/kernel.config"
install -D -m 0644 "$artifact_root/SHA256SUMS" "$mount_dir/lab/BUILD-SHA256SUMS"
sync

(
	cd "$mount_dir"
	sha256sum -c lab/BUILD-SHA256SUMS
) || die "USB artifact readback checksum mismatch"

umount "$mount_dir"
mounted=0
restore_hidden_nodes || die 'could not restore and re-protect backup device nodes'
mount -t vfat -o ro,noatime "$partition" "$mount_dir"
mounted=1
(
	cd "$mount_dir"
	sha256sum -c lab/BUILD-SHA256SUMS
) || die "independent USB artifact readback checksum mismatch"
umount "$mount_dir"
mounted=0
fsck.vfat -n "$partition"

printf '\nUSB is ready and unmounted.\n'
printf 'Device: %s\n' "$device"
printf 'Bootloader SHA-256: %s\n' "$bootloader_hash"
printf 'Kernel SHA-256: %s\n' "$kernel_hash"
