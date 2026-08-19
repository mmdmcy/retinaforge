# MacBookPro11,3 Linux Graphics Notes

NVIDIA GeForce GT 750M / Apple GMUX / Intel-first boot work for this exact
machine lives in this repository. Keep graphics evidence separate from
AHCI/libata patch series even though both tracks share the tree.

## Start here

- **Rebuild this desktop (CachyOS or Debian):**
  [`docs/graphics/recreate.md`](recreate.md)
- **Reproduce Intel-first panel (how-to + scripts):**
  [`docs/graphics/intel-first-repro.md`](intel-first-repro.md)
- **Why Linux cannot copy Big Sur GPU switching:**
  [`docs/graphics/why-not-macos-ags.md`](why-not-macos-ags.md)
- **Latest positive physical validation (2026-08-16):**
  [`docs/source-notes/2026-08-16-hsw-ddi-a-4-lanes.md`](../source-notes/2026-08-16-hsw-ddi-a-4-lanes.md)
  (`force_igd` + `DDI_A_4_LANES` poke; `i915drmfb` 2880×1800)
- **Unreproduced earlier positive (2026-08-01):**
  [`docs/source-notes/2026-08-01-intel-panel-and-display-path.md`](../source-notes/2026-08-01-intel-panel-and-display-path.md)
- **Failed same-recipe retest (2026-08-05):**
  [`docs/source-notes/2026-08-05-intel-panel-path-retest.md`](../source-notes/2026-08-05-intel-panel-path-retest.md)
- **Investigation + Debian/Mint migration plan (2026-08-06):**
  [`docs/source-notes/2026-08-06-intel-panel-investigation-and-migration.md`](../source-notes/2026-08-06-intel-panel-investigation-and-migration.md)
- **`force_igd` connected eDP, 0 DRM modes (2026-08-10):**
  [`docs/source-notes/2026-08-10-uki-intel-attempt-and-xorg-fail.md`](../source-notes/2026-08-10-uki-intel-attempt-and-xorg-fail.md)
  (closed 2026-08-16 by the DDI A 4-lane poke)
- **Indexed eDP handoff experiments (2026-08-10, not default boot):**
  [`docs/source-notes/2026-08-10-edp-handoff-research.md`](../source-notes/2026-08-10-edp-handoff-research.md)
- **DRI_PRIME nouveau offload (2026-08-16):**
  [`docs/source-notes/2026-08-16-dri-prime-nouveau.md`](../source-notes/2026-08-16-dri-prime-nouveau.md)
- **Daily use, Steam, Omarchy, keep macOS:**
  [`max-value-and-omarchy.md`](max-value-and-omarchy.md)
- **Desk power (750M stays on for HDMI/TB; no commute auto-sleep):**
  [`work-battery.md`](work-battery.md)
- **Debian workstation port (stable/patched kernel, same recipes):**
  [`debian-workstation.md`](debian-workstation.md)
- **Plasma Wayland on Iris Pro (verified 2026-08-17):**
  [`wayland.md`](wayland.md)
  ([lab note](../source-notes/2026-08-17-plasma-wayland.md))
- **Hyprland (Command as Super; 0.56 overlay fix; Omarchy Lua pin):**
  [`hyprland.md`](hyprland.md)
  ([lab note](../source-notes/2026-08-17-hyprland.md))
- **Omarchy 4 daily (stock nouveau lid, leave it, 2026-08-19):**
  [`omarchy.md`](omarchy.md),
  [`../source-notes/2026-08-19-omarchy-daily.md`](../source-notes/2026-08-19-omarchy-daily.md)
- **LUKS2 + btrfs durable sync (userspace, 2026-08-19):**
  [`../source-notes/2026-08-19-omarchy-luks-btrfs-sync.md`](../source-notes/2026-08-19-omarchy-luks-btrfs-sync.md)
- **Gaming vs Retina (OpenGL list, why 2880×1800 exists):**
  [`gaming-and-retina.md`](gaming-and-retina.md)
- Upstream graphics review:
  [`docs/source-notes/2026-07-24-macbookpro11-3-graphics-upstream.md`](../source-notes/2026-07-24-macbookpro11-3-graphics-upstream.md)
- Windows Intel enumeration probe:
  [`docs/graphics/windows-intel-probe.md`](windows-intel-probe.md)
- Sanitized aggregate findings:
  [`docs/findings.md`](../findings.md) (graphics subsection)
- Active native-Linux roadmap:
  [`docs/linux-native-roadmap.md`](../linux-native-roadmap.md)
- Storage-first policy and sequencing:
  [`docs/storage-development-plan.md`](../storage-development-plan.md)

## Helper scripts

| Script | Role |
| --- | --- |
| [`macos/scripts/set-gpu-power-prefs-intel.sh`](../../macos/scripts/set-gpu-power-prefs-intel.sh) | macOS: set Intel `gpu-power-prefs` |
| [`scripts/graphics/check-intel-first-panel.sh`](../../scripts/graphics/check-intel-first-panel.sh) | Linux: read-only verify Intel panel path |
| [`scripts/graphics/recreate-desktop.sh`](../../scripts/graphics/recreate-desktop.sh) | One entry: `lid` / `power` / `wayland` / `hyprland` / `omarchy` / `check` / `all` |
| [`scripts/graphics/enable-intel-daily.sh`](../../scripts/graphics/enable-intel-daily.sh) | Install `force_igd` Intel UKI path, DDI 4-lane poke, Intel Xorg, desk power, Wayland DRM pin; keeps eDP-handoff **off** |
| [`scripts/graphics/enable-wayland-intel.sh`](../../scripts/graphics/enable-wayland-intel.sh) | Plasma Wayland autologin (SDDM); restores via `disable-wayland-intel.sh` |
| [`scripts/graphics/check-wayland-intel.sh`](../../scripts/graphics/check-wayland-intel.sh) | Read-only: seat0 Wayland + i915 eDP |
| [`scripts/graphics/debian-initramfs-intel.sh`](../../scripts/graphics/debian-initramfs-intel.sh) | Debian initramfs-tools + cmdline tokens (refuses without `force_igd`) |
| [`scripts/graphics/debian-ukify-intel.sh`](../../scripts/graphics/debian-ukify-intel.sh) | Debian UKI via `ukify` |
| [`scripts/graphics/retinaforge-i915-ddi-4lanes.py`](../../scripts/graphics/retinaforge-i915-ddi-4lanes.py) | Write Haswell `DDI_A_4_LANES` then load i915 |
| [`scripts/graphics/retinaforge-keep-display-awake.sh`](../../scripts/graphics/retinaforge-keep-display-awake.sh) | X11 DPMS off using the user auth file |
| [`scripts/graphics/prime-run`](../../scripts/graphics/prime-run) | `DRI_PRIME=1` wrapper: one OpenGL app on nouveau, Intel keeps the panel |
| [`scripts/graphics/install-wayland-intel.sh`](../../scripts/graphics/install-wayland-intel.sh) | Pin compositors to `/dev/dri/intel-igpu` (no autologin change) |
| [`apps/mbp-panel/`](../../apps/mbp-panel/README.md) | Tray plate: lid/mux/temps, Sleep/Wake, **Run on 750M** (no mux hops) |
| [`scripts/graphics/work-displays.sh`](../../scripts/graphics/work-displays.sh) | Wake 750M and list DRM connectors (native monitors; no layout) |
| [`scripts/graphics/present-layout`](../../scripts/graphics/present-layout) | DisplayLink `extend` or `mirror` |
| [`scripts/graphics/present-off`](../../scripts/graphics/present-off) | Stop DisplayLink; laptop only |

## Scope

This area covers EFI-stub `apple_set_os`, Intel-only boot, Nouveau, Apple GMUX,
dGPU power rails, external displays (including USB DisplayLink as a distinct
path), thermals, and suspend experiments for the tested `MacBookPro11,3` with
Iris Pro + GT 750M.

## Verified recipe (2026-08-16 lid, 2026-08-17 Wayland + Hyprland)

Do **not** start from macOS NVRAM. Full cook-book:
[`recreate.md`](recreate.md). Lid detail:
[`intel-first-repro.md`](intel-first-repro.md).

1. EFI-stub / UKI boot (`apple_set_os`).
2. `apple_gmux.force_igd=1` (CachyOS apple-gmux patch).
3. Set `DDI_A_4_LANES` before i915 probes; then load i915.
4. Confirm `i915drmfb` and eDP 2880×1800.
5. Daily session: Plasma Wayland (`enable-wayland-intel.sh`) **or**
   Hyprland (`recreate-desktop.sh hyprland`). Plasma X11 remains
   recovery (`disable-wayland-intel.sh`). Omarchy: [`omarchy.md`](omarchy.md).
6. Optional OpenGL offload: `DRI_PRIME=1` / `prime-run`. Desk monitors:
   leave the 750M powered. Native HDMI/TB stay on that chip. USB
   DisplayLink is a separate, hotter path.

## Hard stops

- No live GMUX / forced-IGD experimentation after a black screen without a
  recovery plan.
- No writable MSI+NCQ storage trials mixed into graphics boots.
- Do not claim physical rail-off from “driver absent” or “module unloaded”
  alone.
- Do not run the stock Omarchy ISO against the internal SSD (dedicated-drive
  wipe; macOS goes with it). Fun-only on a spare disk or VM.
