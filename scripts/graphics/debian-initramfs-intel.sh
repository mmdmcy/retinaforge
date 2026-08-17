#!/usr/bin/env bash
# Debian initramfs bits for the Intel-lid UKI (initramfs-tools).
# Does not patch apple-gmux. Refuses if force_igd is not a module parameter.
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

if ! command -v update-initramfs >/dev/null 2>&1; then
	echo "update-initramfs not found (not an initramfs-tools Debian?)" >&2
	exit 1
fi

if ! modinfo apple-gmux 2>/dev/null | grep -q 'parm:[[:space:]]*force_igd'; then
	echo "this kernel's apple-gmux has no force_igd parameter." >&2
	echo "Mainline Debian kernels do not. Carry a patched apple-gmux (CachyOS-style)" >&2
	echo "or the lid mux stays DIS. See docs/graphics/recreate.md" >&2
	exit 1
fi

install -d /etc/initramfs-tools
mods=/etc/initramfs-tools/modules
touch "$mods"
if ! grep -qx 'apple-gmux' "$mods"; then
	printf '\n# retinaforge Intel lid (no i915 here)\napple-gmux\nnouveau\n' >>"$mods"
fi
# Never list i915 in the initramfs module list; the DDI poke loads it later.
sed -i '/^i915$/d;/^drm_kms_helper$/d' "$mods" || true

install -d /etc/kernel
cmd=/etc/kernel/cmdline
if [[ ! -f $cmd ]]; then
	# Preserve live root= if we can.
	if [[ -r /proc/cmdline ]]; then
		tr -d '\n' </proc/cmdline >"$cmd"
		printf '\n' >>"$cmd"
	else
		printf 'root=UUID=%s rw\n' "$(findmnt -no UUID /)" >"$cmd"
	fi
fi
# Append tokens if missing (do not strip the operator's extra args).
need=(
	apple_gmux.force_igd=1
	i915.enable_dc=0
	modprobe.blacklist=i915
	plymouth.enable=0
)
line="$(tr -d '\n' <"$cmd")"
for t in "${need[@]}"; do
	if [[ $line != *$t* ]]; then
		line+=" $t"
	fi
done
printf '%s\n' "$line" >"$cmd"

install -Dm644 "${root}/scripts/graphics/nvidia-off-modprobe.conf" /etc/modprobe.d/retinaforge-nvidia-off.conf
install -Dm644 "${root}/scripts/graphics/apple-gmux-intel.conf" /etc/modprobe.d/retinaforge-apple-gmux-intel.conf
install -Dm644 "${root}/scripts/graphics/apple-gmux-softdep.conf" /etc/modprobe.d/retinaforge-apple-gmux-softdep.conf

update-initramfs -u
echo "Debian initramfs updated. Cmdline tokens are in $cmd"
echo "Build a UKI with ukify (docs/graphics/recreate.md). EFI-stub / UKI only — not GRUB linux."
