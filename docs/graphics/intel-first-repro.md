# Intel-first Linux panel reproduction — MacBookPro11,3

**What works today (verified 2026-08-16 lid, 2026-08-17 Plasma Wayland):**
Intel `i915` owns the internal Retina panel at 2880×1800 (`i915drmfb`).
Plasma Wayland on Iris Pro (`KWIN_DRM_NO_AMS=1`). Optional: one OpenGL
app on the GT 750M via `DRI_PRIME=1` without moving the GMUX.

This is a cook-book for `MacBookPro11,3` (Iris Pro `8086:0d26` + GT 750M
`10de:0fe9` + indexed Apple GMUX 4.0.8). Do not generalize to other
`MacBookPro11,x` machines.

The 2026-08-01 `i915drmfb` boot is **historical only**. Repeating macOS
NVRAM + the old UKI did **not** reproduce it (2026-08-05, 2026-08-13).
The repeatable mechanism is below, not `%01` plus luck.

## Two separate problems (both required)

Firmware always starts a Linux UKI boot with the panel mux on **DIS**.

1. **Mux.** Without a boot-time IGD switch, i915 sees a ghost eDP
   (`failed to retrieve link info`). Fix: `apple_gmux.force_igd=1` on a
   **UKI / EFI-stub** boot so `apple_set_os()` has enumerated the iGPU.
   This parameter is a **CachyOS `apple-gmux` patch**, not mainline.
2. **Lanes.** After the mux is on IGD, eDP is **connected** with a valid
   2880×1800 EDID, but DRM advertises **0 modes**. Haswell
   `intel_ddi_max_lanes()` sees `DDI_BUF_CTL_A` without `DDI_A_4_LANES`
   (bit 4, MMIO `0x64000`). Intel GOP never sets that bit when the lid
   was not on IGD at firmware init. i915 then treats PORT_A as **2-lane**;
   2-lane HBR cannot carry 337.75 MHz, so `mode_valid` is `CLOCK_HIGH`.
   Fix: set bit 4 **before** i915’s first probe, then load i915.

Either fix alone is insufficient. `force_igd` without the lane poke is
the 2026-08-10 “connected, 0 modes, Xorg no screens” state.

Evidence:
[`docs/source-notes/2026-08-16-hsw-ddi-a-4-lanes.md`](../source-notes/2026-08-16-hsw-ddi-a-4-lanes.md).

## Lab install (CachyOS + Limine, this workbench)

Keep **macOS** on APFS. Do not mix this with writable MSI+NCQ storage
boots. Do not run a distro ISO that wipes the whole internal disk
(Omarchy’s stock installer does that; see below).

From a clone of this repo, as root, on the **current Intel kernel**
(not LTS — `build-apple-set-os-uki.sh` defaults to `uname -r`):

```bash
sudo ./scripts/graphics/recreate-desktop.sh lid
sudo SKIP_LIMINE=1 KVER=7.1.5-1-cachyos scripts/graphics/build-apple-set-os-uki.sh
```

(Or `sudo scripts/graphics/enable-intel-daily.sh` — same lid installer.)

Ordered CachyOS **and** Debian cook-book: [`recreate.md`](recreate.md).

Then point Limine `default_entry` at the **Intel UKI** leaf. Keep a
numbered **NVIDIA LTS** recovery entry. **Do not** run
`limine-set-default-uki.sh`: it strips extra Intel entries and forces
the UKI to entry 1.

### What `enable-intel-daily.sh` installs

| Path | Role |
| --- | --- |
| `/etc/modprobe.d/retinaforge-nvidia-off.conf` | blacklist proprietary nvidia 470; nouveau stays loadable |
| `/etc/modprobe.d/retinaforge-apple-gmux-intel.conf` | `options apple_gmux force_igd=1` |
| `/etc/modprobe.d/retinaforge-apple-gmux-softdep.conf` | load gmux/nouveau before i915 |
| `/usr/local/sbin/retinaforge-i915-ddi-4lanes.py` | mmap BAR0, set `DDI_A_4_LANES`, `modprobe i915` |
| `/etc/systemd/system/retinaforge-i915-ddi-4lanes.service` | oneshot **before** the display manager |
| `/etc/systemd/system/sddm.service.d/retinaforge-ddi-4lanes.conf` | `After=` / `Wants=` the poke |
| `/etc/X11/xorg.conf.d/40-intel-panel.conf` | modesetting, `BusID PCI:0:2:0`, `kmsdev` by-path |
| `/etc/X11/xorg.conf.d/50-disable-nvidia.conf` | ignore packaged NVIDIA OutputClass |
| `/etc/retinaforge/intel-panel` | stamp: DDI poke may run without the CachyOS cmdline token |
| `install-work-power.sh` | desk: 750M stays on for monitors (`work-battery.md`) |
| `install-wayland-intel.sh` | `/dev/dri/intel-igpu` + KWin DRM env (autologin unchanged) |

The DDI oneshot runs if **either** `apple_gmux.force_igd=1` is on the
cmdline **or** `/etc/retinaforge/intel-panel` exists, so a Debian UKI
can use the stamp. NVIDIA recovery must remove that stamp
(`disable-nvidia-off.sh`).

It also **disables** the eDP-handoff unit (that profile can wedge SSH).

### What the Intel UKI must contain

`scripts/graphics/mkinitcpio-intel-uki.conf`:

- `MODULES=(apple-gmux nouveau)` — **no i915**, **no kms hook**
- FILES: the three `retinaforge-*.conf` drop-ins above
- cmdline tokens (plus normal `root=`):
  `apple_gmux.force_igd=1 i915.enable_dc=0 modprobe.blacklist=i915 plymouth.enable=0`

Boot order that worked:

1. EFI stub → `apple_set_os()` → iGPU enumerated
2. Initramfs: apple-gmux `force_igd` switches mux to IGD; nouveau loads;
   i915 stays out
3. Root: `retinaforge-i915-ddi-4lanes.service` writes `0x64000` bit 4
   (`0x81` → `0x91` in the lab), then `modprobe i915 enable_dc=0`
4. SDDM / Xorg modesetting on Iris Pro

Journal lines to look for:

```text
retinaforge-i915-ddi-4lanes: i915 not loaded
retinaforge-i915-ddi-4lanes: DDI_BUF_CTL_A before=0x00000081 4lanes=False
retinaforge-i915-ddi-4lanes: DDI_BUF_CTL_A after=0x00000091 4lanes=True
retinaforge-i915-ddi-4lanes: fb0=i915drmfb
```

### Verify (must pass)

```bash
sudo scripts/graphics/check-intel-first-panel.sh
sudo scripts/graphics/verify-intel-uki-boot.sh
```

| Check | Expected |
| --- | --- |
| PCI | `8086:0d26` |
| fb0 | `i915drmfb` |
| i915 eDP | connected, kernel mode **2880×1800** (empty modes = still 2-lane) |
| debugfs | `i915_dp_max_lane_count=4` |
| switcheroo | `IGD:+:Pwr` |
| Xorg | modesetting + glamor on Iris Pro, output often named `eDP-2` |

`gpu-policy` may still read discrete on Linux. That is **not** a failure;
`force_igd` already switched the mux. `DIS: … Pwr` is a thermal warning,
not a panel-ownership failure.

## Optional: OpenGL on the GT 750M (not AGS)

Confirmed 2026-08-16 with the mux still on IGD:

```bash
DRI_PRIME=0 glxinfo -B    # Iris Pro
DRI_PRIME=1 glxinfo -B    # nouveau NVE7
scripts/graphics/prime-run glxgears
```

Intel keeps the lid. Only that process renders on nouveau. Vulkan stayed
on Intel. Proprietary nvidia 470 is **not** this path. `echo OFF` on
switcheroo would stop offload (needs DIS powered).

This is not Big Sur Automatic Graphics Switching.
[`docs/graphics/why-not-macos-ags.md`](why-not-macos-ags.md),
[`docs/source-notes/2026-08-16-dri-prime-nouveau.md`](../source-notes/2026-08-16-dri-prime-nouveau.md).

## Recovery

- Limine → **NVIDIA LTS** after `sudo scripts/graphics/disable-nvidia-off.sh`
  (restores NVIDIA Xorg, removes Intel `40-intel-panel.conf`).
- Firmware boot picker → macOS (NVRAM / Apple recovery).
- Black lid but SSH up: GMUX backlight to max, restart display manager.
  Do **not** live-`echo IGD`/`DIS`.
- eDP-handoff profile: opt-in only, never default (SSH wedge, 2026-08-10).

## Hard stops / failed experiments (do not retry as “the fix”)

| Experiment | Result |
| --- | --- |
| macOS `gpu-policy=%01` + cold off + UKI, no `force_igd` | mux stays `DIS:+`; ghost eDP |
| Byte-identical 2026-08-01 UKI after verified NVRAM | still ghost eDP (2026-08-13) |
| `force_igd` only (i915 in initramfs, no lane poke) | eDP connected, **0 modes**, Xorg no screens |
| `video=eDP-*:2880x1800@60e` | `User-defined mode not supported` (`CLOCK_HIGH`) |
| debugfs `i915_dp_force_lane_count=4` | `max_lane_count` stays 2; modes stay empty |
| Live `echo IGD` after boot | switcheroo can say `IGD:+` while the panel stays on the other driver |
| DIS-first eDP handoff v1–v3 as **default** boot | v3 lost SSH; do not re-enable |
| Stock Omarchy ISO on the internal SSD | dedicated-drive wipe; **erases macOS** |

Live GMUX forcing after a black screen is how you lose the lid. SSH-first.

## Distro notes (including Omarchy)

Graphics success is **not** “whatever distro as long as it is Linux.”

Required on any reinstall:

1. **Keep macOS.**
2. Boot via **EFI stub / UKI** so `apple_set_os()` runs. Bare Limine/GRUB
   `protocol: linux` skipped Set OS on this machine.
3. A kernel whose `apple-gmux` has **`force_igd`**, or an equivalent mux
   switch before i915. **Mainline and stock Arch/Omarchy kernels may not
   have this CachyOS patch.**
4. The DDI A 4-lane poke (userspace script, or the unbuilt DMI quirk in
   `patches/0003-i915-mbp11-3-ddi-a-4-lanes.patch`).
5. i915 delayed until after that poke.
6. Xorg **or** Plasma Wayland **or** Hyprland pinned to Iris Pro
   (`/dev/dri/intel-igpu`). NVIDIA OutputClass ignored. Plasma:
   [`wayland.md`](wayland.md) (`KWIN_DRM_NO_AMS=1`). Hyprland:
   [`hyprland.md`](hyprland.md) (`AQ_NO_ATOMIC=1`). Omarchy port:
   [`omarchy.md`](omarchy.md). `disable-wayland-intel.sh` restores
   Plasma X11 on the CachyOS/SDDM path.
7. `check-intel-first-panel.sh` must pass. PCI presence is not enough.

**Omarchy:** Hyprland on this lid is proven; the ISO is still a
**manual** dual-boot / replace-Linux-only port. Do **not** use the stock
ISO against the internal SSD as a dedicated-drive wipe. Quattro’s “Free
space” dual-boot is documented for Windows-style leftover space; shrink
**APFS from macOS**, never from Linux. Keep a macOS partition (recovery
when the lid goes black). Prefer **btrfs on LUKS2**, not ext4-on-dm-crypt.
Port `force_igd` + DDI poke; then `dofile` the Lua hardware pin. Written down:
[`omarchy.md`](omarchy.md),
[`max-value-and-omarchy.md`](max-value-and-omarchy.md).

## Daily controls (tray plate)

A small taskbar jewel lives in [`apps/mbp-panel/`](../../apps/mbp-panel/README.md).
It shows whether the lid is on `i915`, whether the unused 750M is powered,
and package/fan readings. Sleep/Wake write switcheroo `OFF`/`ON` only.
They do not flip the mux. The **?** on the plate is the reminder; **Run on
750M** wakes the chip and starts `DRI_PRIME=1` so you do not memorize
`prime-run`. Long form (Steam, Omarchy, keep macOS):
[`max-value-and-omarchy.md`](max-value-and-omarchy.md). Named OpenGL
titles and why 2880×1800 exists:
[`gaming-and-retina.md`](gaming-and-retina.md).

```bash
sudo pacman -S --needed python-pyqt6 ttf-ibm-plex polkit
sudo ./apps/mbp-panel/install.sh
retinaforge-mbp-panel &
```

## External displays

Native HDMI / Thunderbolt-style outputs on this chassis stay on the
**GT 750M** even when the lid is Intel. Keep that chip **powered** at a
desk (`sudo ./scripts/graphics/install-work-power.sh`, then the desktop
display settings). `sudo retinaforge-work-displays.sh` wakes it and
lists connectors; it does not place screens.

USB DisplayLink can drive 1080p panels with the 750M left off; hot if
sustained. That is `present-on`, not the work-dock path.

Debian port (pinned kernel, same recipes):
[`debian-workstation.md`](debian-workstation.md).
Desk power (750M stays on):
[`work-battery.md`](work-battery.md).

## Historical record (not the recipe)

- 2026-08-01 unreproduced positive:
  [`docs/source-notes/2026-08-01-intel-panel-and-display-path.md`](../source-notes/2026-08-01-intel-panel-and-display-path.md)
- 2026-08-05 same-recipe miss:
  [`docs/source-notes/2026-08-05-intel-panel-path-retest.md`](../source-notes/2026-08-05-intel-panel-path-retest.md)
- Mux always DIS on Linux UKI:
  [`docs/source-notes/2026-08-08-limine-timeline-and-forced-dis-test.md`](../source-notes/2026-08-08-limine-timeline-and-forced-dis-test.md)
- `force_igd` 0-modes:
  [`docs/source-notes/2026-08-10-uki-intel-attempt-and-xorg-fail.md`](../source-notes/2026-08-10-uki-intel-attempt-and-xorg-fail.md)
- 08-01 UKI retest:
  [`docs/source-notes/2026-08-13-historical-uki-retest.md`](../source-notes/2026-08-13-historical-uki-retest.md)
- Plasma Wayland (2026-08-17):
  [`docs/source-notes/2026-08-17-plasma-wayland.md`](../source-notes/2026-08-17-plasma-wayland.md)

macOS NVRAM scripts remain in `macos/scripts/` for Apple-side experiments.
They are **not** why the 2026-08-16 Linux desktop works.
