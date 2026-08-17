#!/usr/bin/env bash
# orchestrate-intel-boot.sh — remote Intel-first boot cycle (no console needed).
#
# Run from neo/controller with SSH to mbp113-linux. Chains:
#   Linux prep → one-shot EFI boot macOS → NVRAM from macOS → bless Limine → reboot
#
# Cold power-off is ideal but not automatable remotely; macOS reboot into Limine
# is the best unattended path. Use macOS prepare + shutdown -h only when at the machine.

set -euo pipefail

LINUX_HOST="${LINUX_HOST:-mbp113-linux}"
MACOS_HOST="${MACOS_HOST:-mbp113-macos}"
# Clone path on the Linux side. Override; never hardcode a local username.
ROOT_ON_LINUX="${ROOT_ON_LINUX:-}"
MACOS_WAIT_SEC="${MACOS_WAIT_SEC:-300}"
LINUX_WAIT_SEC="${LINUX_WAIT_SEC:-300}"

log() { printf '[orchestrate] %s\n' "$*"; }
die() { printf '[orchestrate] ERROR: %s\n' "$*" >&2; exit 1; }

ssh_linux() { ssh -o BatchMode=yes -o ConnectTimeout=15 "$LINUX_HOST" "$@"; }
ssh_macos() { ssh -o BatchMode=yes -o ConnectTimeout=15 "$MACOS_HOST" "$@"; }

if [[ -z $ROOT_ON_LINUX ]]; then
	ROOT_ON_LINUX="$(ssh_linux 'printf %s "$HOME/Documents/github/retinaforge"')"
fi

wait_for_host() {
	local host=$1 max=$2
	local start now
	start=$(date +%s)
	while true; do
		if ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" true 2>/dev/null; then
			return 0
		fi
		now=$(date +%s)
		if ((now - start >= max)); then
			return 1
		fi
		sleep 10
	done
}

log "Phase 1: Linux prep on ${LINUX_HOST}"
ssh_linux exec /bin/bash -s <<EOF
set -euo pipefail
cd "${ROOT_ON_LINUX}"
sudo "${ROOT_ON_LINUX}/scripts/graphics/enable-intel-daily.sh"
sudo "${ROOT_ON_LINUX}/scripts/graphics/limine-set-default-uki.sh"
sudo /usr/local/sbin/retinaforge-gmux-backlight-floor.sh 2>/dev/null || sudo "${ROOT_ON_LINUX}/scripts/graphics/retinaforge-gmux-backlight-floor.sh"
sudo efibootmgr -n 0080
echo "scheduled one-shot boot -> macOS (0080)"
EOF

log "Phase 2: reboot Linux -> macOS"
ssh_linux 'sudo systemctl reboot' || true
sleep 15

log "Phase 3: wait for ${MACOS_HOST} (up to ${MACOS_WAIT_SEC}s)"
wait_for_host "$MACOS_HOST" "$MACOS_WAIT_SEC" || die "macOS did not come up on SSH"

log "Phase 4: macOS NVRAM + bless Limine"
ssh_macos exec /bin/bash -s <<'EOF'
set -euo pipefail
root="${HOME}/Documents/github/retinaforge"
[[ -d "$root" ]] || { echo "retinaforge repo missing on macOS (expected \$HOME/Documents/github/retinaforge)"; exit 1; }
"$root/macos/scripts/prepare-intel-from-macos.sh"
# Bless Limine EFI on the Linux ESP (vfat partition 3 on this lab disk).
limine_efi=$(diskutil list | awk '/EFI.*Linux|EFI/ {print; getline; print}' | head -1 || true)
# Use bless with explicit mount when Linux ESP is mounted at /Volumes/* during macOS
esp=""
for m in /Volumes/*; do
  [[ -f "$m/EFI/limine/limine_x64.efi" ]] && esp="$m" && break
done
if [[ -z "$esp" ]]; then
  diskutil mount disk0s3 2>/dev/null || diskutil mount disk1s3 2>/dev/null || true
  for m in /Volumes/*; do
    [[ -f "$m/EFI/limine/limine_x64.efi" ]] && esp="$m" && break
  done
fi
[[ -n "$esp" ]] || { echo "Limine ESP not found"; exit 1; }
echo "Blessing Limine on ${esp}"
sudo bless --folder "$esp/EFI/limine" --setBoot --file "$esp/EFI/limine/limine_x64.efi"
sudo nvram boot-args=""
echo "Rebooting into Limine UKI path..."
sudo reboot
EOF

log "Phase 5: wait for ${LINUX_HOST} (up to ${LINUX_WAIT_SEC}s)"
wait_for_host "$LINUX_HOST" "$LINUX_WAIT_SEC" || die "Linux did not return after macOS reboot"

log "Phase 6: verify"
ssh_linux "sudo ${ROOT_ON_LINUX}/scripts/graphics/verify-intel-uki-boot.sh; sudo ${ROOT_ON_LINUX}/scripts/graphics/check-intel-first-panel.sh 2>/dev/null || true"

log "Done."
