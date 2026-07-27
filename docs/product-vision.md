# Apple AHCI Linux Workbench Product Vision

Current status: Big Sur reference environment working; macOS strict persistence
measured fast, so a narrow Linux AHCI/libata investigation is active again.

Proposed storage-repository name: `macbookpro11-3-ahci-latency`. Keep the
existing local and remote names until the dirty worktree is reviewed and the
rename can update links, remotes, repository metadata, and documentation
atomically.

Create graphics work separately as `macbookpro11-3-linux-graphics` only when
storage is no longer blocking Linux tests. The storage repository should own
AHCI/libata evidence, strict-sync behavior, block-layer prototypes, and storage
patches. The graphics repository should own EFI-stub `apple_set_os`, Intel-only
boot, NVIDIA/Nouveau, GMUX, external-display, power, and suspend experiments.
An umbrella repository is unnecessary until both projects have real artifacts
that need a shared landing page.

## Product Direction

- Make affected Intel Apple laptops practical, secure Linux work machines
  without replacing healthy storage hardware.
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
- Compare Apple and Linux controller/cache/power/command state before writing a
  patch; the exact missing mechanism is not yet proven.
- Get a measurable local fix first; upstream authorship follows only after a
  missing Linux behavior is proven and the candidate passes hardware testing.
- Prefer contribution to upstream Linux over a permanent private kernel fork.
- Treat AHCI storage, Apple ACPI, and NVIDIA/Nouveau/GMUX as separate upstream
  tracks with separate evidence and patch series.
- Use the exact DMI model in both future repository names. Do not let the
  storage project become a general MacBook tuning collection or mix unrelated
  storage and graphics kernel patch series.
