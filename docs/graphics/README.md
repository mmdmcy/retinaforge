# MacBookPro11,3 Linux Graphics Notes

NVIDIA GeForce GT 750M / Apple GMUX / Intel-first boot work for this exact
machine lives in this repository. It is deferred until Linux storage testing is
no longer blocked.

## Start here

- Upstream graphics review:
  [`docs/source-notes/2026-07-24-macbookpro11-3-graphics-upstream.md`](../source-notes/2026-07-24-macbookpro11-3-graphics-upstream.md)
- Storage-first policy and sequencing:
  [`docs/storage-development-plan.md`](../storage-development-plan.md)
- Roadmap context:
  [`docs/linux-driver-upstream-roadmap.md`](../linux-driver-upstream-roadmap.md)

## Scope

This area covers EFI-stub `apple_set_os`, Intel-only boot, Nouveau, Apple GMUX,
dGPU power rails, external displays, thermals, and suspend experiments for the
tested `MacBookPro11,3` with Iris Pro + GT 750M.

Do not mix graphics driver experiments into AHCI/libata patch series. Keep
evidence separate even though both tracks share this repository.
