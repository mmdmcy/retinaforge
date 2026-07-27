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

## Current diagnostic patch

`0001-ahci-mbp11-3-opt-in-msi-diagnostic.patch` is an external-appliance
experiment, not a proposed upstream fix. Bounded read-only MSI tests passed,
but MSI plus NCQ writes produced three timeout/reset waves on the physical
target. Never use it for an installed root filesystem and never infer writable
safety from the read-only result. The only narrower profile prepared forces
non-NCQ, but it was never physically run, its deterministic rebuild was
canceled, and the disposable partition no longer exists. It is not currently
authorized or a ready artifact.
