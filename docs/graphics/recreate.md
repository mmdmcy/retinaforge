# Recreate the MacBookPro11,3 Linux desktop

This is the cook-book to rebuild the working CachyOS desk — and to port
the same stack to **Debian** — without replaying the lab. Hardware is
Late-2013 15-inch `MacBookPro11,3`: Iris Pro `8086:0d26` + GT 750M
`10de:0fe9` + indexed Apple GMUX 4.0.8.

Keep **macOS** on APFS. Shrink APFS only from macOS. Skip LUKS on this
SSD. Do not run a dedicated-drive installer against the internal Apple
disk.

Verified on this workbench:

| Piece | Status |
| --- | --- |
| Intel lid `i915drmfb` 2880×1800 | 2026-08-16 |
| Desk power (750M stays on for HDMI/TB) | 2026-08-17 |
| Plasma Wayland on Iris Pro | 2026-08-17 |
| Hyprland 0.56 on Iris Pro (Command = Super) | 2026-08-17 |

## Layers (order matters)

```text
1. EFI-stub / UKI boot          apple_set_os() enumerates the iGPU
2. apple_gmux.force_igd=1       mux to IGD (patched apple-gmux, not mainline)
3. DDI A 4-lane poke, then i915  userspace MMIO, then modprobe i915 enable_dc=0
4. Desk power                   750M stays Pwr (native monitors)
5. Plasma Wayland, Hyprland, or Omarchy   SDDM or Omarchy session + Intel DRM pin
                                          (`hyprland.md`, `omarchy.md`)
```

Skip a layer and the next one is meaningless. Power scripts do not light
the panel. Wayland does not switch the mux.

## This workbench (CachyOS + Limine, lid already Intel)

From a clone of this repo:

```bash
sudo ./scripts/graphics/recreate-desktop.sh lid       # once per install
# rebuild Intel UKI, set Limine default to it, reboot that entry
sudo SKIP_LIMINE=1 ./scripts/graphics/build-apple-set-os-uki.sh
sudo ./scripts/graphics/recreate-desktop.sh check
sudo ./scripts/graphics/recreate-desktop.sh wayland   # Plasma Wayland
sudo ./scripts/graphics/recreate-desktop.sh hyprland  # Hyprland, Command=Super (SDDM)
sudo ./scripts/graphics/recreate-desktop.sh omarchy   # DRM pin + Lua snippet; no SDDM
sudo ./scripts/graphics/check-wayland-intel.sh
```

If `fb0` is already `i915drmfb` (this lab after a working Intel UKI boot):

```bash
sudo ./scripts/graphics/recreate-desktop.sh all
```

Revert Wayland to Plasma X11:

```bash
sudo ./scripts/graphics/disable-wayland-intel.sh
```

Keep a numbered **NVIDIA LTS** Limine entry. Do not run
`limine-set-default-uki.sh` (it strips extra Intel entries).

## Debian (future install)

Same layers. Distro-agnostic scripts: `enable-intel-daily.sh`,
`install-work-power.sh`, `enable-wayland-intel.sh`. Debian-only helpers
for initramfs + UKI.

### Packages

```bash
sudo apt install python3 systemd udev bash \
  systemd-ukify systemd-boot-efi binutils \
  initramfs-tools \
  sddm plasma-workspace kwin-wayland weston \
  xserver-xorg-core xserver-xorg-video-modesetting \
  power-profiles-daemon
```

Use **SDDM + Plasma**, not GNOME’s GDM, if you want this Wayland recipe
unchanged. Do **not** install TLP next to `power-profiles-daemon`. Do
**not** install `xserver-xorg-video-intel` — Xorg is **modesetting** on
`PCI:0:2:0`. Optional tray: `python3-pyqt6`, `polkitd`, `fonts-ibm-plex`.

### Kernel / mux (the hard Debian part)

`apple_gmux.force_igd=1` is a **CachyOS apple-gmux patch**. Stock Debian
kernels do **not** have it. The t2linux wiki `force_igd` text is for **T2**
Macs, not this 2013 Haswell. Without that parameter the mux stays
`DIS:+` and i915 sees a ghost eDP.

Options:

1. Carry a kernel (or out-of-tree `apple-gmux`) that exposes `force_igd`
   (`modinfo apple-gmux | grep force_igd` must show a parm).
2. Do **not** substitute live `echo IGD` / `DIS`.

The DDI 4-lane poke is userspace (`retinaforge-i915-ddi-4lanes.py`) and
does not need a patched i915. Optional in-tree equivalent:
`patches/0003-i915-mbp11-3-ddi-a-4-lanes.patch`.

### After the patched kernel is installed

```bash
sudo ./scripts/graphics/enable-intel-daily.sh
sudo ./scripts/graphics/debian-initramfs-intel.sh
sudo ./scripts/graphics/debian-ukify-intel.sh
```

Boot **that UKI** (systemd-boot extra entry, or GRUB `chainloader` of
the EFI file). GRUB `linux` protocol skipped `apple_set_os()` on this
machine — the lid will not come up.

Then:

```bash
sudo ./scripts/graphics/check-intel-first-panel.sh
sudo ./scripts/graphics/enable-wayland-intel.sh
sudo ./scripts/graphics/check-wayland-intel.sh
```

`debian-initramfs-intel.sh` **exits** if `force_igd` is missing. That is
intentional.

## What each installer writes

| Command | Effect |
| --- | --- |
| `enable-intel-daily.sh` | nvidia-off + gmux `force_igd` modprobe, DDI oneshot before the DM, Intel Xorg drop-ins, `/etc/retinaforge/intel-panel` stamp, desk power, Wayland DRM pin (`/dev/dri/intel-igpu`). Does **not** rewrite the bootloader. |
| `install-work-power.sh` | 750M stays on; `COMMUTE_SLEEP=0`; Intel backlight floor only |
| `enable-wayland-intel.sh` | SDDM Wayland + Plasma autologin; stashes `10-x11.conf` **out of** `sddm.conf.d`; writes `/etc/sddm.conf` last; unmasks `plasma-kwin_wayland.service`; frees VT 1 before start. `PREFER=hyprland` selects `hyprland-intel.desktop`. |
| `recreate-desktop.sh omarchy` | `enable-intel-daily.sh` only (DDI + DRM pin + Lua snippet). Does **not** rewrite SDDM. |
| `disable-wayland-intel.sh` | Plasma X11 autologin again |

Details: [`intel-first-repro.md`](intel-first-repro.md),
[`work-battery.md`](work-battery.md), [`wayland.md`](wayland.md),
[`hyprland.md`](hyprland.md), [`omarchy.md`](omarchy.md).

## Acceptance

- Lid: `i915drmfb`, eDP 2880×1800, `check-intel-first-panel.sh` passes.
- Session: `loginctl` seat0 `Type=wayland`. Plasma: `Desktop=KDE`,
  `plasmashell` + `kwin_wayland`. Hyprland: `Desktop=Hyprland`.
  `check-wayland-intel.sh` passes.
- Desk: GT 750M `Pwr`, `powerprofilesctl get` is `balanced`.
- Unplug AC: 750M stays on (no commute auto-sleep).
- HDMI/TB: nouveau connectors can show `connected`; place them in Plasma
  display settings. They are **not** on Intel.

## Hard stops (do not “fix” a black lid with these)

- Live `echo IGD` / `DIS`
- Re-enable `i915.enable_dc`
- TLP next to power-profiles-daemon
- `powertop --auto-tune`, SATA ALPM, MSI+NCQ mixed with graphics
- Stock Omarchy/Debian dedicated-drive wipe of the internal SSD
- GRUB `linux` protocol instead of UKI/EFI-stub
- Mainline `apple-gmux` without `force_igd` (Debian default)
- Leaving `*.bak*` files in `/etc/sddm.conf.d/` (SDDM 0.21 reads **every**
  file in that directory)
- `systemctl restart sddm` while an old X11 session still owns VT 1
  (`HELPER_TTY_ERROR`) — `sddm-free-vt.sh` exists for this
- Masked `plasma-kwin_wayland.service` (X11 bring-up leftover)
- Hyprland `AQ_DRM_DEVICES` pointing at `/dev/dri/by-path/…` (colons)
- Hyprland 0.56 keys `input:touchpad:tap`, `misc:vfr`,
  `dwindle:pseudotile` (overlay; see [`hyprland.md`](hyprland.md))
- `source = hyprland-retinaforge.conf` inside Omarchy 4
  (`hyprland.lua` — use `dofile(…lua)` instead)

Native HDMI/Thunderbolt stay on the GT 750M even when the lid is Intel.
A Wayland desktop does not change that wiring.
