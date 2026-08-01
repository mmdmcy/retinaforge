# MacBookPro11,3 Linux Graphics Notes

NVIDIA GeForce GT 750M / Apple GMUX / Intel-first boot work for this exact
machine lives in this repository. Keep graphics evidence separate from
AHCI/libata patch series even though both tracks share the tree.

## Start here

- **Latest physical validation (2026-08-01):**
  [`docs/source-notes/2026-08-01-intel-panel-and-display-path.md`](../source-notes/2026-08-01-intel-panel-and-display-path.md)
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

## Scope

This area covers EFI-stub `apple_set_os`, Intel-only boot, Nouveau, Apple GMUX,
dGPU power rails, external displays (including USB DisplayLink as a distinct
path), thermals, and suspend experiments for the tested `MacBookPro11,3` with
Iris Pro + GT 750M.

## Verified recipe (aggregate)

1. Write Intel `gpu-power-prefs` from macOS.
2. Boot Linux through a Limine **UKI / EFI-stub** entry (not bare
   `protocol: linux`).
3. Confirm `i915drmfb` and internal eDP 2880×1800.
4. Optionally switcheroo `OFF` the discrete client; re-check after boots.
5. Prefer DisplayLink only for short presenting sessions if used; do not
   equate it with native GT 750M outputs.

## Hard stops

- No live GMUX / forced-IGD experimentation after a black screen without a
  recovery plan.
- No writable MSI+NCQ storage trials mixed into graphics boots.
- Do not claim physical rail-off from “driver absent” or “module unloaded”
  alone.
