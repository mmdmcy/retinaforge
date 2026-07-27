#!/usr/bin/env bash
# Create or remove a one-time GRUB entry that restores upstream NCQ behavior.
#
# This script never edits GRUB's default kernel command line or reboots. The
# optional --arm-next-boot writes GRUB's single-use next_entry only; it must be
# used while the owner is present to unlock LUKS after the subsequent reboot.
set -euo pipefail

readonly custom_file=/etc/grub.d/40_custom
readonly marker_begin='# BEGIN apple-ahci-ncq-test'
readonly marker_end='# END apple-ahci-ncq-test'
entry_id=apple-ahci-ncq-test
entry_label='Apple AHCI NCQ test (one boot)'

usage() {
  cat <<'EOF'
Usage:
  create-ncq-test-entry.sh --install --yes [--enable-fua] [--replace]
                            [--arm-next-boot]
  create-ncq-test-entry.sh --remove --yes

Actions:
  --install             Append a temporary current-kernel entry without
                        libata.force=noncq, then regenerate GRUB.
  --enable-fua          Also add libata.fua=1 to the temporary entry.
  --replace             Replace an existing marked test entry before install.
  --arm-next-boot       Set that entry for exactly the next boot. Does not
                        reboot and requires --install.
  --remove              Remove only the marked temporary entry, then
                        regenerate GRUB.
  --yes                 Required acknowledgement of the boot configuration
                        change.
  -h, --help            Show this help.

The stock GRUB default and /etc/default/grub are never modified. Use only when
the owner is present and can enter the normal LUKS passphrase after reboot.
EOF
}

action=
arm_next_boot=0
enable_fua=0
replace_entry=0
confirmed=0

while (($#)); do
  case "$1" in
    --install)
      action=install
      shift
      ;;
    --remove)
      action=remove
      shift
      ;;
    --arm-next-boot)
      arm_next_boot=1
      shift
      ;;
    --enable-fua)
      enable_fua=1
      shift
      ;;
    --replace)
      replace_entry=1
      shift
      ;;
    --yes)
      confirmed=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  printf 'Run this script as root.\n' >&2
  exit 2
fi
if [[ -z $action || $confirmed -ne 1 ]]; then
  printf 'An action and --yes are required.\n' >&2
  usage >&2
  exit 2
fi
if ((arm_next_boot)) && [[ $action != install ]]; then
  printf '--arm-next-boot can only be used with --install.\n' >&2
  exit 2
fi
if ((enable_fua)) && [[ $action != install ]]; then
  printf '--enable-fua can only be used with --install.\n' >&2
  exit 2
fi
if ((replace_entry)) && [[ $action != install ]]; then
  printf '--replace can only be used with --install.\n' >&2
  exit 2
fi
if [[ ! -f $custom_file ]]; then
  printf 'Expected GRUB custom file is missing: %s\n' "$custom_file" >&2
  exit 1
fi

if ((enable_fua)); then
  entry_id=apple-ahci-ncq-fua-test
  entry_label='Apple AHCI NCQ + FUA test (one boot)'
fi

has_entry() {
  grep -Fqx "$marker_begin" "$custom_file"
}

remove_marked_entry() {
  local temporary_file
  temporary_file=$(mktemp)
  awk -v begin="$marker_begin" -v end="$marker_end" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "$custom_file" > "$temporary_file"
  install -m 0755 -o root -g root "$temporary_file" "$custom_file"
  rm -f "$temporary_file"
}

regenerate_grub() {
  update-grub
  grub-script-check /boot/grub/grub.cfg
}

if [[ $action == remove ]]; then
  if ! has_entry; then
    printf 'No %s entry is installed.\n' "$entry_id"
    exit 0
  fi

  remove_marked_entry
  grub-editenv - unset next_entry || true
  regenerate_grub
  printf 'Removed %s. The stock GRUB behavior is unchanged.\n' "$entry_id"
  exit 0
fi

if has_entry; then
  if ((replace_entry)); then
    remove_marked_entry
  else
    printf 'Refusing to duplicate an existing marked entry; use --replace.\n' >&2
    exit 2
  fi
fi

kernel_version=$(uname -r)
kernel_image="/vmlinuz-$kernel_version"
initrd_image="/initrd.img-$kernel_version"
boot_uuid=$(findmnt -n -o UUID /boot)

if [[ -z $boot_uuid || ! -r "/boot$kernel_image" || ! -r "/boot$initrd_image" ]]; then
  printf 'Could not derive a bootable current-kernel entry.\n' >&2
  exit 1
fi

kernel_arguments=()
while IFS= read -r argument; do
  case "$argument" in
    ''|BOOT_IMAGE=*|libata.force=noncq|libata.fua=*)
      continue
      ;;
  esac
  kernel_arguments+=("$argument")
done < <(tr ' ' '\n' </proc/cmdline)

if ((enable_fua)); then
  kernel_arguments+=(libata.fua=1)
fi

test_command_line=${kernel_arguments[*]}
if [[ $test_command_line != *'root='* || $test_command_line == *'libata.force=noncq'* ]]; then
  printf 'Refusing to generate an unsafe command line.\n' >&2
  exit 1
fi
if ((enable_fua)) && [[ $test_command_line != *'libata.fua=1'* ]]; then
  printf 'Refusing to generate an entry without the requested FUA setting.\n' >&2
  exit 1
fi

{
  printf '\n%s\n' "$marker_begin"
  printf "menuentry '%s' --id '%s' {\n" "$entry_label" "$entry_id"
  printf '  recordfail\n'
  printf '  load_video\n'
  printf '  insmod gzio\n'
  printf '  insmod part_gpt\n'
  printf '  insmod ext2\n'
  printf '  search --no-floppy --fs-uuid --set=root %s\n' "$boot_uuid"
  printf "  echo 'Loading Linux %s with %s...'\n" "$kernel_version" "$entry_label"
  printf '  linux %s %s\n' "$kernel_image" "$test_command_line"
  printf "  echo 'Loading initial ramdisk...'\n"
  printf '  initrd %s\n' "$initrd_image"
  printf '}\n%s\n' "$marker_end"
} >> "$custom_file"

regenerate_grub

if ((arm_next_boot)); then
  grub-reboot "$entry_id"
  printf 'Armed %s for exactly the next reboot. No reboot was started.\n' "$entry_id"
else
  printf 'Installed %s. The stock GRUB default remains unchanged.\n' "$entry_id"
fi
