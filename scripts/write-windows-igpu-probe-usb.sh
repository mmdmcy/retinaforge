#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Safely provision a removable USB with the transient Windows Intel probe.
set -euo pipefail

repo_root=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
artifact_root=${ARTIFACT_ROOT:-$repo_root/build/windows-igpu-probe/artifact}
device=
confirmation=

usage() {
	cat <<'EOF'
Usage: write-windows-igpu-probe-usb.sh --device /dev/sdX [--confirm TOKEN]

Without --confirm, this performs read-only validation and prints the exact
token for the destructive invocation. The entire selected USB is erased.
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

for command in realpath lsblk findmnt swapon sha256sum wipefs sgdisk \
	partprobe udevadm mkfs.vfat mount umount fsck.vfat blockdev cp sync; do
	command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

artifact_root=$(realpath "$artifact_root")
case "$artifact_root/" in
	"$repo_root/build/"*/) ;;
	*) die "ARTIFACT_ROOT must remain below $repo_root/build" ;;
esac
[[ -f $artifact_root/EFI/BOOT/BOOTX64.EFI ]] || die "probe bootloader is missing"
[[ -f $artifact_root/SHA256SUMS ]] || die "probe checksum manifest is missing"
(
	cd "$artifact_root"
	sha256sum -c SHA256SUMS
) || die "artifact checksum verification failed"

[[ -b $device ]] || die "not a block device: $device"
device=$(readlink -f "$device")
name=$(basename "$device")
[[ $name =~ ^sd[b-z]$ ]] || die "only /dev/sd[b-z] whole-disk devices are accepted"
[[ $device != /dev/sda ]] || die "the system disk is permanently refused"
[[ -r /sys/class/block/$name/removable ]] || die "missing removable-device metadata"
[[ $(</sys/class/block/$name/removable) == 1 ]] || die "$device is not marked removable"

transport=$(lsblk -dn -o TRAN "$device" | tr -d '[:space:]')
[[ $transport == usb ]] || die "$device transport is '$transport', not USB"
size_bytes=$(lsblk -dnb -o SIZE "$device" | tr -d '[:space:]')
model=$(lsblk -dn -o MODEL "$device" | sed 's/[[:space:]]*$//')
serial=$(lsblk -dn -o SERIAL "$device" | tr -d '[:space:]')
[[ $size_bytes =~ ^[0-9]+$ ]] || die "could not determine device size"
((size_bytes >= 4 * 1024 * 1024 * 1024)) || die "USB is smaller than 4 GiB"
((size_bytes <= 256 * 1024 * 1024 * 1024)) || die "USB is larger than 256 GiB"
[[ -n $model && -n $serial ]] || die "USB model or serial is unavailable"

while IFS= read -r node; do
	[[ -n $node ]] || continue
	findmnt -rn -S "$node" >/dev/null 2>&1 && die "$node is mounted"
	if swapon --noheadings --raw --show=NAME 2>/dev/null | grep -Fxq "$node"; then
		die "$node is active swap"
	fi
done < <(lsblk -nrpo NAME "$device")

root_source=$(findmnt -n -o SOURCE /)
if lsblk -snrpo NAME "$root_source" 2>/dev/null | grep -Fxq "$device"; then
	die "$device backs the running root filesystem"
fi
artifact_source=$(findmnt -n -o SOURCE -T "$artifact_root")
if lsblk -snrpo NAME "$artifact_source" 2>/dev/null | grep -Fxq "$device"; then
	die "artifact source is on $device and would be erased"
fi

token_model=${model//:/_}
token="ERASE:${device}:${size_bytes}:${token_model}:${serial}"
printf 'Validated candidate USB (no writes performed):\n'
lsblk -o NAME,PATH,TRAN,RM,SIZE,MODEL,SERIAL,FSTYPE,LABEL,MOUNTPOINTS "$device"
printf '\nExisting signatures (still untouched):\n'
if [[ -r $device ]]; then
	wipefs -n "$device" || true
else
	printf 'Unavailable without elevated block-device access.\n'
fi

if [[ -z $confirmation ]]; then
	printf '\nTo erase this exact device, rerun with:\n'
	printf '  --confirm %q\n' "$token"
	exit 2
fi
[[ $confirmation == "$token" ]] || die "confirmation token does not match this USB"
((EUID == 0)) || die "destructive invocation must run as root (use sudo)"

mount_dir=$(mktemp -d /tmp/mbp-igpu-usb.XXXXXX)
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
	--change-name=1:MBP_IGPU \
	"$device"
partprobe "$device"
udevadm settle

partition="${device}1"
[[ -b $partition ]] || die "expected partition did not appear: $partition"
mkfs.vfat -F 32 -n MBP_IGPU "$partition"
mount -t vfat -o rw,noatime "$partition" "$mount_dir"
mounted=1
cp -r "$artifact_root/." "$mount_dir/"
sync
umount "$mount_dir"
mounted=0
blockdev --flushbufs "$device"

mount -t vfat -o ro "$partition" "$mount_dir"
mounted=1
(
	cd "$mount_dir"
	sha256sum -c SHA256SUMS
) || die "USB readback checksum mismatch"
bootloader_hash=$(sha256sum "$mount_dir/EFI/BOOT/BOOTX64.EFI" | cut -d' ' -f1)
umount "$mount_dir"
mounted=0
fsck.vfat -n "$partition"

printf '\nUSB is ready and unmounted.\n'
printf 'Device: %s\n' "$device"
printf 'Model: %s\n' "$model"
printf 'Serial: %s\n' "$serial"
printf 'BOOTX64.EFI SHA-256: %s\n' "$bootloader_hash"
printf 'Do not perform the first boot unattended.\n'
