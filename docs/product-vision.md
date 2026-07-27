# MacBookPro11,3 Workbench Product Vision

Current status: Big Sur reference environment working; macOS strict persistence
measured fast, so a narrow Linux AHCI/libata investigation is active again.
Native workstation notes, Linux storage work, and deferred NVIDIA/GMUX notes
now live in this single repository.

This repository is the centralized public home for the tested
`MacBookPro11,3` configuration. Do not split the human-facing notes into
parallel untracked trees. Keep evidence tracks separate inside the repo:

- `macos/` owns Big Sur native development and compatibility builds.
- Root `docs/`, `scripts/`, `patches/`, and `tools/` own AHCI/libata storage
  evidence and diagnostic kernels.
- `docs/graphics/` plus the graphics source notes own NVIDIA/Nouveau/GMUX
  planning until storage no longer blocks Linux tests.

An extra umbrella repository is unnecessary. Separate future repository names
are only for upstream-shaped kernel series if a maintainer process requires a
narrower patch-only tree. Until then, keep one remoted source of truth here.

## Product Direction

- Make this exact Intel Apple laptop practical: usable Big Sur workstation
  first, then a secure Linux path without replacing healthy storage hardware.
- Prefer a narrow, measurable upstream driver correction over a permanent
  private kernel fork or a distribution-specific workaround.
- Treat an existing upstream behavior as the preferred solution when it solves
  the problem; do not create a patch merely to claim one.

## Current Product Loop

1. Capture a sanitized, bounded reproduction of the latency failure.
2. Test one reversible variable at a time with a bootable fallback.
3. Prove the smallest fix under normal work and write stress.
4. Rebase a genuinely missing behavior onto upstream Linux and submit it only
   after local proof.

## Data And Privacy Direction

- Keep raw captures, trace files, network details, disk serials, encryption
  metadata, and session transcripts out of Git.
- Publish only sanitized hardware identifiers, aggregate latency figures, and
  a reviewable patch when the work is ready for upstream discussion.
- Keep RetinaForge `local-only/` material on the machine, never in this repo.

## Risk Positioning

- Preserve LUKS and ext4 integrity semantics throughout investigation.
- Never use a destructive benchmark against the root filesystem.
- Never remove a known-good boot path before validating a candidate.

## Roadmap Notes

- Storage latency and reliability come before NVIDIA/GMUX work.
- A custom `.deb` kernel is a temporary test vehicle only if current upstream
  behavior cannot solve the problem.
- The macOS `fsync()`/`F_FULLFSYNC` discriminator measured fast strict
  persistence, including after a cold boot; compare Apple and Linux state
  before changing Linux.
- Prefer contribution to upstream Linux over a permanent private kernel fork.
- Treat AHCI storage, Apple ACPI, and NVIDIA/Nouveau/GMUX as separate evidence
  tracks with separate patch series, even while they share this repository.
