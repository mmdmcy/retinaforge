# Debian workstation on this MacBookPro11,3

CachyOS proved the Intel Retina lid, Plasma Wayland, **and** Hyprland
0.56. **Debian** (pinned / patched kernel) is still the distro to take
to work. Do not treat “install Debian” (or Omarchy) as a graphics
shortcut — the lid recipe still has to be ported. The desk power profile
**is** distro-agnostic. Omarchy: [`omarchy.md`](omarchy.md).

The one ordered cook-book (CachyOS *and* Debian) is
[`recreate.md`](recreate.md). This page is the Debian-shaped checklist.

Keep **macOS** on APFS. Shrink APFS only from macOS. On this SSD prefer
**btrfs on LUKS2** (or plain ext4), not **ext4-on-dm-crypt**. Do not run
a dedicated-drive installer against the internal Apple SSD.

## Two layers (both required)

| Layer | Recreatable today | Notes |
| --- | --- | --- |
| Desk power (750M stays on for monitors) | **Yes** | `sudo ./scripts/graphics/install-work-power.sh` |
| Intel lid (`i915drmfb` 2880×1800) + Plasma Wayland | **Port** | UKI + `force_igd` (not in mainline) + DDI poke + SDDM Wayland |

Power alone does not give you a Debian desktop on this panel. Without
the lid recipe, Debian boots the mux on NVIDIA (`DIS:+`) or a black
eDP.

## Packages

```bash
sudo apt install python3 systemd udev bash \
  systemd-ukify systemd-boot-efi binutils initramfs-tools \
  sddm plasma-workspace kwin-wayland weston \
  xserver-xorg-core xserver-xorg-video-modesetting \
  power-profiles-daemon
```

Do **not** install TLP next to `power-profiles-daemon`. Do **not**
install `xserver-xorg-video-intel` — the Xorg pin is **modesetting** on
`PCI:0:2:0`.

Tray plate (optional): `python3-pyqt6`, `polkitd`, `fonts-ibm-plex`.

Use **SDDM + Plasma**. GNOME/GDM is untested with this mux recipe.

## Install order

1. Patched `apple-gmux` with `force_igd` (`modinfo apple-gmux` must list
   the parm). Stock Debian kernels do **not**. t2linux wiki `force_igd`
   is the wrong generation.
2. `sudo ./scripts/graphics/enable-intel-daily.sh`
3. `sudo ./scripts/graphics/debian-initramfs-intel.sh` (refuses if
   `force_igd` is missing)
4. `sudo ./scripts/graphics/debian-ukify-intel.sh` and **boot that UKI**
   (EFI-stub). GRUB `linux` skipped Set OS here.
5. `sudo ./scripts/graphics/check-intel-first-panel.sh` must pass.
6. `sudo ./scripts/graphics/enable-wayland-intel.sh`
7. `sudo ./scripts/graphics/check-wayland-intel.sh`

NVIDIA proprietary 470 is a **recovery** boot, not the work desktop.

## Work monitors

On this generation the **internal panel** can be Intel while **HDMI /
Thunderbolt** stay on the GT 750M. A work desk therefore needs the
750M **powered**. The power profile keeps it that way by default (this
machine is not used on a commute).

After the chip is awake, place screens in Plasma display settings.
`sudo retinaforge-work-displays.sh` only wakes + lists connectors.

USB DisplayLink (`scripts/graphics/present-on`) is the Intel-only extra
screen path. Hot. Presenting, not the all-day dock.

## What not to “optimize” for work

- Do not auto-sleep the 750M on AC (kills native HDMI/TB).
- Do not set power-saver while docked.
- Do not re-enable `i915.enable_dc` (this panel needed it off).
- Do not `powertop --auto-tune`, SATA ALPM experiments, or MSI+NCQ
  storage patches on the work install.
- Do not live-`echo IGD`/`DIS`.
- Do not leave `*.bak*` in `/etc/sddm.conf.d/` (SDDM reads every file).

## Acceptance

- Lid: `i915drmfb`, eDP 2880×1800.
- Session: seat0 `Type=wayland`, Plasma.
- Desk: `DIS` is `Pwr`, `powerprofilesctl get` is `balanced`.
- Extra monitor: DRM connector other than eDP shows `connected`;
  desktop can place it.
- Unplug AC: 750M stays on (no commute auto-sleep).
