# Patches

Place only focused, reviewable kernel patches here.

Do not publish prototypes whose motivating hypothesis failed. Retain those in
ignored local storage and summarize the negative result in `docs/findings.md`.

Each patch must include:

- the matched PCI or DMI hardware scope;
- the observed failure mode;
- why a generic Linux configuration is insufficient;
- the recovery path;
- before/after trace evidence with sensitive fields removed.

## Current diagnostic patches

`0001-ahci-mbp11-3-opt-in-msi-diagnostic.patch` is an external-appliance
experiment, not a proposed upstream fix. Bounded read-only MSI tests passed,
but MSI plus NCQ writes produced three timeout/reset waves on the physical
target. Never use it for an installed root filesystem and never infer writable
safety from the read-only result. The only narrower profile prepared forces
non-NCQ, but it was never physically run, its deterministic rebuild was
canceled, and the disposable partition no longer exists. It is not currently
authorized or a ready artifact.

`0002-ahci-mbp11-3-flush-reg-sample.patch` is an opt-in `libahci` diagnostic for
the flush-reg-stack appliance. It samples AHCI host/port registers around
outstanding `FLUSH CACHE EXT` so long post-issue delays can be classified as
PxCI-held versus PxCI-cleared-early. It does not change issue or completion
policy and must not be treated as a performance fix.

`0003-i915-mbp11-3-ddi-a-4-lanes.patch` is a DMI-scoped sketch for
`intel_ddi_a_force_4_lanes()` on `MacBookPro11,3`. Apple EFI leaves
`DDI_A_4_LANES` unset when Linux boots with the mux on DIS, so stock i915
treats PORT_A as 2-lane and rejects 2880×1800 (`CLOCK_HIGH`). The lab daily
path is the userspace MMIO poke in `scripts/graphics/retinaforge-i915-ddi-4lanes.py`;
this patch is the kernel-shaped equivalent and has not been rebuilt or booted
yet. Add `#include <linux/dmi.h>` if the target `intel_ddi.c` does not already
pull it in. Never mix this with writable MSI+NCQ storage boots.
