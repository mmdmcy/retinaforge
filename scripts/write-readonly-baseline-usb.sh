#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Safely provision a removable USB with the read-only baseline EFI appliance.
set -euo pipefail

repo_root=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
artifact_root=${ARTIFACT_ROOT:-$repo_root/build/readonly-baseline-v7.1.3/artifact}
device=
confirmation=

usage() {
	cat <<'EOF'
Usage: write-readonly-baseline-usb.sh --device /dev/sdX [--confirm TOKEN]

The first invocation without --confirm performs only validation and prints the
exact token required for the destructive invocation. The entire selected USB
is erased. The script never auto-selects a device.
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
		*)
			die "unknown argument: $1"
			;;
	esac
done

[[ -n $device ]] || {
	usage >&2
	exit 2
}
[[ -b $device ]] || die "not a block device: $device"
device=$(readlink -f "$device")
name=$(basename "$device")
[[ $name =~ ^sd[b-z]$ ]] || \
	die "only removable /dev/sd[b-z] whole-disk devices are accepted"
[[ $device != /dev/sda ]] || die "the ThinkPad system disk is permanently refused"
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

bootloader_image=$artifact_root/EFI/BOOT/BOOTX64.EFI
kernel_image=$artifact_root/lab/vmlinuz
[[ -f $bootloader_image ]] || die "baseline EFI bootloader not found: $bootloader_image"
[[ -f $kernel_image ]] || die "baseline kernel not found: $kernel_image"
(
	cd "$artifact_root"
	sha256sum -c SHA256SUMS
) || die "artifact checksum verification failed"

token="ERASE:${device}:${size_bytes}"
printf 'Validated candidate USB (no writes performed):\n'
lsblk -o NAME,PATH,TRAN,RM,SIZE,MODEL,FSTYPE,LABEL,MOUNTPOINTS "$device"
printf '\nExisting signatures (still untouched):\n'
wipefs -n "$device" || true

if [[ -z $confirmation ]]; then
	printf '\nTo erase this exact device, rerun with:\n'
	printf '  --confirm %q\n' "$token"
	exit 2
fi
[[ $confirmation == "$token" ]] || die "confirmation token does not match this device and size"
((EUID == 0)) || die "destructive invocation must run as root (use sudo)"

mount_dir=$(mktemp -d /tmp/mbp-ahci-usb.XXXXXX)
mounted=0
cleanup() {
	local rc=$?
	trap - EXIT INT TERM
	if ((mounted)); then
		umount "$mount_dir" 2>/dev/null || true
	fi
	rmdir "$mount_dir" 2>/dev/null || true
	exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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

mount -t vfat -o rw,noatime "$partition" "$mount_dir"
mounted=1
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

bootloader_hash=$(sha256sum "$bootloader_image" | cut -d' ' -f1)
kernel_hash=$(sha256sum "$kernel_image" | cut -d' ' -f1)

umount "$mount_dir"
mounted=0
fsck.vfat -n "$partition"

printf '\nUSB is ready and unmounted.\n'
printf 'Device: %s\n' "$device"
printf 'Bootloader SHA-256: %s\n' "$bootloader_hash"
printf 'Kernel SHA-256: %s\n' "$kernel_hash"
