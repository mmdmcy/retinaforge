#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build a self-contained EFI diagnostic kernel for the first native baseline.
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
build_root=${BUILD_ROOT:-$repo_root/build}
kernel_source=${KERNEL_SOURCE:-$build_root/linux-v7.1.3}
work_root=${WORK_ROOT:-$build_root/readonly-baseline-v7.1.3}
kernel_out=$work_root/kernel-out
initramfs_root=$work_root/initramfs
initramfs_archive=$kernel_out/mbp-readonly-initramfs.cpio
artifact_root=$work_root/artifact
grub_config=${GRUB_CONFIG:-$repo_root/scripts/grub/readonly-baseline-grub.cfg}
init_script=${INIT_SCRIPT:-$repo_root/scripts/initramfs/readonly-baseline-init}
initramfs_static_binaries=${INITRAMFS_STATIC_BINARIES:-}
initramfs_dynamic_binaries=${INITRAMFS_DYNAMIC_BINARIES:-}
enable_filesystem_stack=${ENABLE_FILESYSTEM_STACK:-0}
jobs=${JOBS:-$(nproc)}
clean=${CLEAN:-1}

expected_commit=199c9959d3a9b53f346c221757fc7ac507fbac50
expected_version=7.1.3
source_date_epoch=1783165517
kernel_localversion=${KERNEL_LOCALVERSION:--mbp-ahci-baseline}
expected_kernel_release=${EXPECTED_KERNEL_RELEASE:-$expected_version$kernel_localversion}
kernel_cmdline=${KERNEL_CMDLINE:-'rdinit=/init console=tty0 loglevel=7 printk.time=1 nomodeset panic=30'}
expected_kernel_diff=${EXPECTED_KERNEL_DIFF:-}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

for command in git make gcc install realpath ldd awk sha256sum file objdump cpio cmp \
	find sort touch gzip grub-mkstandalone grub-script-check; do
	require_command "$command"
done

[[ $(uname -m) == x86_64 ]] || die "this appliance must be built on x86_64"
[[ -e $kernel_source/.git ]] || die "kernel source not found: $kernel_source"
[[ -f $grub_config ]] || die "GRUB configuration not found: $grub_config"
[[ -f $init_script ]] || die "initramfs init not found: $init_script"
grub-script-check "$grub_config"

kernel_source=$(realpath "$kernel_source")
work_root=$(realpath -m "$work_root")
build_parent=$(realpath -m "$build_root")
case "$work_root/" in
	"$build_parent"/*/) ;;
	*) die "WORK_ROOT must remain below $build_parent" ;;
esac
[[ $work_root != "$build_parent" ]] || die "refusing to use the build root itself"

actual_commit=$(git -C "$kernel_source" rev-parse HEAD)
[[ $actual_commit == "$expected_commit" ]] || \
	die "expected Linux $expected_version commit $expected_commit, found $actual_commit"
if [[ -n $expected_kernel_diff ]]; then
	expected_kernel_diff=$(realpath "$expected_kernel_diff")
	[[ -f $expected_kernel_diff ]] || die "expected kernel diff not found: $expected_kernel_diff"
	cmp -s "$expected_kernel_diff" \
		<(git -C "$kernel_source" diff --no-ext-diff --binary -- drivers/ata/ahci.c) || \
		die "kernel source diff does not exactly match $expected_kernel_diff"
	[[ -z $(git -C "$kernel_source" status --porcelain --untracked-files=normal | \
		grep -v '^ M drivers/ata/ahci.c$') ]] || \
		die "kernel source contains changes outside the reviewed AHCI patch"
else
	[[ -z $(git -C "$kernel_source" status --porcelain --untracked-files=no) ]] || \
		die "kernel source has tracked modifications"
fi
actual_version=$(make -s -C "$kernel_source" LOCALVERSION= kernelversion)
[[ $actual_version == "$expected_version" ]] || \
	die "expected kernel version $expected_version, found $actual_version"

busybox=$(command -v busybox)
lspci=$(command -v lspci)
hdparm=$(command -v hdparm)
[[ -n $busybox && -x $busybox ]] || die "busybox-static is required"
file "$busybox" | grep -q 'statically linked' || die "busybox must be statically linked"
[[ -n $lspci && -x $lspci ]] || die "pciutils is required"
[[ -n $hdparm && -x $hdparm ]] || die "hdparm is required"

if [[ $clean == 1 ]]; then
	rm -rf -- "$work_root"
elif [[ $clean == 0 ]]; then
	rm -rf -- "$initramfs_root" "$artifact_root"
	rm -f -- \
		"$initramfs_archive" \
		"$kernel_out/usr/initramfs_data.cpio" \
		"$kernel_out/usr/initramfs_inc_data" \
		"$kernel_out/usr/initramfs_data.o" \
		"$kernel_out/usr/built-in.a"
else
	die "CLEAN must be 0 or 1"
fi
[[ $enable_filesystem_stack == 0 || $enable_filesystem_stack == 1 ]] || \
	die "ENABLE_FILESYSTEM_STACK must be 0 or 1"
install -d -m 0755 \
	"$kernel_out" \
	"$initramfs_root/bin" \
	"$initramfs_root/dev" \
	"$initramfs_root/etc" \
	"$initramfs_root/mnt" \
	"$initramfs_root/proc" \
	"$initramfs_root/run" \
	"$initramfs_root/sys" \
	"$initramfs_root/usr/share/misc" \
	"$artifact_root/EFI/BOOT" \
	"$artifact_root/lab"

install -m 0755 "$busybox" "$initramfs_root/bin/busybox"
while IFS= read -r applet; do
	[[ -n $applet ]] || continue
	[[ -e $initramfs_root/bin/$applet || -L $initramfs_root/bin/$applet ]] && continue
	ln -s busybox "$initramfs_root/bin/$applet"
done < <("$busybox" --list)

copy_dynamic_binary() {
	local source=$1
	local destination=$2
	local library

	install -D -m 0755 "$source" "$initramfs_root$destination"
	while IFS= read -r library; do
		[[ -f $library ]] || continue
		install -D -m 0755 "$library" "$initramfs_root$library"
	done < <(ldd "$source" | awk \
		'$2 == "=>" && $3 ~ /^\// { print $3 } $1 ~ /^\// { print $1 }' | sort -u)
}

copy_dynamic_binary "$lspci" /bin/lspci
copy_dynamic_binary "$hdparm" /bin/hdparm
for binary in $initramfs_dynamic_binaries; do
	[[ -x $binary ]] || die "extra dynamic initramfs binary is not executable: $binary"
	copy_dynamic_binary "$binary" "/bin/$(basename "$binary")"
done
if [[ -f /usr/share/misc/pci.ids ]]; then
	install -m 0644 /usr/share/misc/pci.ids "$initramfs_root/usr/share/misc/pci.ids"
fi
if [[ $enable_filesystem_stack == 1 && -f /etc/mke2fs.conf ]]; then
	install -D -m 0644 /etc/mke2fs.conf "$initramfs_root/etc/mke2fs.conf"
fi
install -m 0755 \
	"$init_script" \
	"$initramfs_root/init"
for binary in $initramfs_static_binaries; do
	[[ -x $binary ]] || die "extra initramfs binary is not executable: $binary"
	file "$binary" | grep -q 'statically linked' || \
		die "extra initramfs binary must be statically linked: $binary"
	install -m 0755 "$binary" "$initramfs_root/bin/$(basename "$binary")"
done

# Do not embed the builder's UID, timestamps, or absolute home-directory path.
# Kbuild runs in kernel_out, so this stable relative filename is sufficient.
find "$initramfs_root" -exec touch -h -d "@$source_date_epoch" {} +
(
	cd "$initramfs_root"
	find . -mindepth 1 -printf '%P\0' | LC_ALL=C sort -z | \
		cpio --null --create --format=newc --owner=0:0 --reproducible \
		> "$initramfs_archive"
)

make -C "$kernel_source" O="$kernel_out" LOCALVERSION= x86_64_defconfig
"$kernel_source/scripts/config" --file "$kernel_out/.config" \
	--set-str LOCALVERSION "$kernel_localversion" \
	--set-str INITRAMFS_SOURCE "$(basename "$initramfs_archive")" \
	--set-str CMDLINE "$kernel_cmdline" \
	-d LOCALVERSION_AUTO \
	-e MODULES \
	-d DRM_NOUVEAU \
	-m DRM_I915 \
	-d HIBERNATION \
	-e IKCONFIG \
	-e IKCONFIG_PROC \
	-e PRINTK_TIME \
	-e DEBUG_FS \
	-e TRACING \
	-e FTRACE \
	-e BLK_DEV_IO_TRACE \
	-e EFI \
	-e EFI_STUB \
	-e EFIVAR_FS \
	-e DEVTMPFS \
	-e DEVTMPFS_MOUNT \
	-e BLK_DEV_INITRD \
	-e INITRAMFS_COMPRESSION_GZIP \
	-e CMDLINE_BOOL \
	-e CMDLINE_OVERRIDE \
	-e SCSI \
	-e SCSI_CONSTANTS \
	-e BLK_DEV_SD \
	-e CHR_DEV_SG \
	-e ATA \
	-e ATA_ACPI \
	-e ATA_VERBOSE_ERROR \
	-e SATA_AHCI \
	-e USB_XHCI_HCD \
	-e USB_STORAGE \
	-e USB_UAS \
	-e VFAT_FS \
	-e NLS_CODEPAGE_437 \
	-e NLS_ISO8859_1 \
	-e DRM \
	-e DRM_SIMPLEDRM \
	-e DRM_FBDEV_EMULATION \
	-e SYSFB_SIMPLEFB \
	-e FRAMEBUFFER_CONSOLE \
	-e HID \
	-e HID_GENERIC \
	-e USB_HID \
	-e HID_APPLE \
	-e HWMON \
	-e SENSORS_APPLESMC \
	-e SENSORS_CORETEMP

if [[ $enable_filesystem_stack == 1 ]]; then
	"$kernel_source/scripts/config" --file "$kernel_out/.config" \
		-e EXT4_FS \
		-e BLK_DEV_DM \
		-e DM_CRYPT \
		-e CRYPTO_XTS \
		-e CRYPTO_AES_NI_INTEL
fi

make -C "$kernel_source" O="$kernel_out" LOCALVERSION= olddefconfig
make -C "$kernel_source" O="$kernel_out" LOCALVERSION= prepare

required_config=(
	'CONFIG_EFI_STUB=y'
	'CONFIG_CMDLINE_OVERRIDE=y'
	'CONFIG_SATA_AHCI=y'
	'CONFIG_USB_XHCI_HCD=y'
	'CONFIG_USB_STORAGE=y'
	'CONFIG_VFAT_FS=y'
	'CONFIG_DRM_SIMPLEDRM=y'
	'CONFIG_DRM_FBDEV_EMULATION=y'
	'CONFIG_SYSFB_SIMPLEFB=y'
	'CONFIG_FRAMEBUFFER_CONSOLE=y'
	'CONFIG_SENSORS_APPLESMC=y'
)
for setting in "${required_config[@]}"; do
	grep -Fxq "$setting" "$kernel_out/.config" || die "missing required kernel setting: $setting"
done
if [[ $enable_filesystem_stack == 1 ]]; then
	for setting in \
		'CONFIG_EXT4_FS=y' \
		'CONFIG_BLK_DEV_DM=y' \
		'CONFIG_DM_CRYPT=y' \
		'CONFIG_CRYPTO_XTS=y' \
		'CONFIG_CRYPTO_AES_NI_INTEL=y'; do
		grep -Fxq "$setting" "$kernel_out/.config" || \
			die "missing filesystem-stack kernel setting: $setting"
	done
fi
grep -Fxq "CONFIG_INITRAMFS_SOURCE=\"$(basename "$initramfs_archive")\"" "$kernel_out/.config" || \
	die "built-in initramfs path was not retained"
grep -Fxq '# CONFIG_DRM_NOUVEAU is not set' "$kernel_out/.config" || \
	die "Nouveau must not be built into this storage-only appliance"

kernel_release=$(make -s -C "$kernel_source" O="$kernel_out" LOCALVERSION= kernelrelease)
[[ $kernel_release == "$expected_kernel_release" ]] || \
	die "unexpected kernel release: $kernel_release"

export KBUILD_BUILD_USER=codexresearch
export KBUILD_BUILD_HOST=linux-builder
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP='2026-07-04 11:45:17 UTC'
export SOURCE_DATE_EPOCH=$source_date_epoch
make -C "$kernel_source" O="$kernel_out" LOCALVERSION= -j"$jobs" bzImage

# Verify the complete built-in initramfs byte-for-byte. Checking only /init
# would miss an accidentally stale helper, shared library, or configuration
# file in the kernel image.
cmp -s "$initramfs_archive" <(gzip -dc "$kernel_out/usr/initramfs_inc_data") || \
	die "embedded initramfs does not match the reviewed archive"
embedded_init_hash=$(gzip -dc "$kernel_out/usr/initramfs_inc_data" | \
	cpio -i --quiet --to-stdout init | sha256sum | cut -d' ' -f1)
source_init_hash=$(sha256sum "$init_script" | cut -d' ' -f1)
[[ $embedded_init_hash == "$source_init_hash" ]] || \
	die "embedded init does not match the reviewed initramfs source"

kernel_image=$artifact_root/lab/vmlinuz
bootloader_image=$artifact_root/EFI/BOOT/BOOTX64.EFI
install -m 0644 "$kernel_out/arch/x86/boot/bzImage" "$kernel_image"
install -m 0644 "$kernel_out/.config" "$artifact_root/lab/kernel.config"
install -m 0644 "$grub_config" "$artifact_root/lab/grub.cfg"

grub-mkstandalone \
	--format=x86_64-efi \
	--output="$bootloader_image" \
	--modules='part_gpt fat search search_label linux normal configfile echo reboot halt' \
	"boot/grub/grub.cfg=$grub_config"

for efi_image in "$bootloader_image" "$kernel_image"; do
	objdump -f "$efi_image" | grep 'file format pei-x86-64' >/dev/null || \
		die "$efi_image is not an x86-64 PE executable"
	objdump -x "$efi_image" | grep 'Subsystem.*EFI application' >/dev/null || \
		die "$efi_image does not advertise the EFI application subsystem"
done

(
	cd "$artifact_root"
	sha256sum \
		EFI/BOOT/BOOTX64.EFI \
		lab/vmlinuz \
		lab/grub.cfg \
		lab/kernel.config \
		> SHA256SUMS
)

printf 'Built bootloader: %s\n' "$bootloader_image"
printf 'Built kernel: %s\n' "$kernel_image"
printf 'Kernel release: %s\n' "$kernel_release"
printf 'Bootloader SHA-256: %s\n' "$(sha256sum "$bootloader_image" | cut -d' ' -f1)"
printf 'Kernel SHA-256: %s\n' "$(sha256sum "$kernel_image" | cut -d' ' -f1)"
