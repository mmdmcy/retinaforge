# MacBookPro11,3 Linux Graphics Notes

NVIDIA GeForce GT 750M / Apple GMUX / Intel-first boot work for this exact
machine lives in this repository. Keep graphics evidence separate from
AHCI/libata patch series even though both tracks share the tree.

## Start here

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
| [`scripts/graphics/enable-intel-daily.sh`](../../scripts/graphics/enable-intel-daily.sh) | Install `force_igd` Intel UKI path, DDI 4-lane poke, Intel Xorg; keeps eDP-handoff **off** |
| [`scripts/graphics/retinaforge-i915-ddi-4lanes.py`](../../scripts/graphics/retinaforge-i915-ddi-4lanes.py) | Write Haswell `DDI_A_4_LANES` then load i915 |
| [`scripts/graphics/retinaforge-keep-display-awake.sh`](../../scripts/graphics/retinaforge-keep-display-awake.sh) | X11 DPMS off using the user auth file |
| [`scripts/graphics/prime-run`](../../scripts/graphics/prime-run) | `DRI_PRIME=1` wrapper: one OpenGL app on nouveau, Intel keeps the panel |
| [`scripts/graphics/present-layout`](../../scripts/graphics/present-layout) | `extend` or `mirror` |
| [`scripts/graphics/present-off`](../../scripts/graphics/present-off) | Stop DisplayLink; laptop only |

## Scope

This area covers EFI-stub `apple_set_os`, Intel-only boot, Nouveau, Apple GMUX,
dGPU power rails, external displays (including USB DisplayLink as a distinct
path), thermals, and suspend experiments for the tested `MacBookPro11,3` with
Iris Pro + GT 750M.

## Verified recipe (2026-08-16)

Do **not** start from macOS NVRAM. The working Linux path is UKI `force_igd`
+ DDI A 4-lane poke, then `check-intel-first-panel.sh`. Full cook-book:
[`intel-first-repro.md`](intel-first-repro.md).

1. EFI-stub / UKI boot (`apple_set_os`).
2. `apple_gmux.force_igd=1` (CachyOS apple-gmux patch).
3. Set `DDI_A_4_LANES` before i915 probes; then load i915.
4. Confirm `i915drmfb` and eDP 2880×1800.
5. Optional OpenGL offload: `DRI_PRIME=1` / `prime-run` (nouveau, Intel keeps
   the lid). Optional cooler idle: switcheroo `OFF` (disables that offload).
6. DisplayLink only for short presenting; not native GT 750M outputs.

## Hard stops

- No live GMUX / forced-IGD experimentation after a black screen without a
  recovery plan.
- No writable MSI+NCQ storage trials mixed into graphics boots.
- Do not claim physical rail-off from “driver absent” or “module unloaded”
  alone.
- Do not run the stock Omarchy ISO against the internal SSD (dedicated-drive
  wipe; macOS goes with it). Fun-only on a spare disk or VM.
