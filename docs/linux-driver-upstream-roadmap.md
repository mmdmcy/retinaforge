# Linux Driver And Upstream Contribution Roadmap

Last updated: 2026-07-18

Current status: paused. Big Sur remains installed, the temporary scratch
partition was removed, and APFS was restored to the full internal SSD and
verified. The lab USB no longer contains macOS recovery. No build,
repartitioning, USB provisioning, or physical reboot is authorized merely by
this roadmap.

## Objective

Make the Late-2013 `MacBookPro11,3` a responsive Linux work laptop with its
original Apple/Samsung SSD, then upstream any genuinely missing Linux behavior
as a narrow, reviewable contribution. A local fix comes first; résumé value and
upstream authorship are welcome outcomes, not substitutes for proof.

This is not one monolithic "MacBook driver." The storage controller, Apple ACPI
data, NVIDIA/Nouveau graphics, GMUX switching, Broadcom Wi-Fi, thermals, and
suspend paths are separate subsystems with separate maintainers and tests.

The concrete storage implementation branches and their decision gates are in
[`storage-development-plan.md`](storage-development-plan.md). That plan is the
bridge between the measurements here and an actual patch or prototype.

## Known Baseline

- Machine: `MacBookPro11,3`, 2.6 GHz quad-core Intel i7, 16 GB DDR3L.
- Storage: `APPLE SSD SM1024F`, firmware `UXM6JA1Q`, controller `144d:1600`.
- Graphics: Intel Iris Pro plus NVIDIA GK107M/GeForce GT 750M Mac Edition,
  PCI ID `10de:0fe9`.
- Wi-Fi: Broadcom BCM4360, PCI ID `14e4:43a0`; Linux Wi-Fi worked with
  `broadcom-sta-dkms`/`wl` and is not a new-driver priority.
- Linux's existing `144d:1600` no-MSI AHCI quirk was active and selected legacy
  INTx in the physical current-upstream baseline.
- Ordinary writes completed quickly, but the first following durability or
  non-write operation took roughly 0.8 seconds inside the SSD behavior.
- NCQ, non-NCQ, FUA, both ATA flush commands, write-through caching, power
  controls, and barrier suppression all failed acceptance testing.
- Apple's inspected AHCI driver contains no hidden controller setup or private
  fast flush command for this device.
- Big Sur `11.7.11` now runs cool and responsively on the same internal SSD.
- On 2026-07-17, internal-APFS macOS testing measured mean ordinary `fsync()`
  latency of 1.134 ms and mean strict `F_FULLFSYNC` latency of 6.863 ms across
  12 one-mebibyte writes. The strict path is fast on macOS.
- After a full reboot, a second identical run measured 1.107 ms ordinary
  `fsync()` and 13.082 ms strict `F_FULLFSYNC`, with no workload intentionally
  running besides the probe.
- Big Sur exposes MSI enabled with NCQ queue depth 32. A local opt-in Linux
  `7.1.3` diagnostic cleared only the no-MSI flag for `MacBookPro11,3` plus PCI
  ID `144d:1600`.
- The first physical diagnostic stage passed with MSI, non-NCQ queue depth 1,
  a read-only internal SSD, and no ATA fault. The MSI-plus-NCQ bounded-read
  stage also passed at queue depth 32 with 555 handled AHCI MSI interrupts and
  no ATA fault.
- The writable MSI-plus-NCQ stage failed during `mkfs.ext4`: 22 queued-write
  timeout reports occurred across three 30-second waves, each followed by a
  hard SATA link reset. The upstream no-MSI default is therefore still
  required for writable NCQ on this target.
- The stock legacy-INTx Linux 7.1.3 stack remained error-free but developed
  repeated roughly 1.1-second flush tails after sustained filesystem activity.

## Phase 0: Preserve The Working Reference System

1. Keep Big Sur working and make a current backup before more destructive work.
2. The 128 GB recovery-bootstrap USB was later erased with explicit permission
   and became the `MBP_AHCI` lab medium. Before any new destructive work,
   recreate and test a recovery route; do not assume that USB still has macOS
   recovery.
3. Record the exact Big Sur version, hardware report, SSD identity, and battery
   condition without committing serial numbers or private account data.
4. Do not reinstall Linux merely to repeat already-rejected AHCI combinations.

## Phase 1: Run The Decisive macOS Storage Test (complete)

Build and run `tools/macos-fullfsync-probe.c` from the internal APFS volume by
following `macos-fullfsync-test.md`. Repeat enough samples to compare ordinary
`fsync()` with `F_FULLFSYNC` tail latency.

The initial and cold-boot runs both selected Branch A: strict Linux driver work
is justified. A sanitized Apple state snapshot is recorded in
`docs/findings.md`. The physical Linux baseline then identified interrupt mode
as one concrete difference, so the project has moved into staged MSI
diagnostics rather than broad controller guessing.

### Branch A: `F_FULLFSYNC` is fast

The first result shows that macOS reaches a fast strict-persistence behavior
not yet reproduced on Linux. Before turning a diagnostic into a production
change:

1. The cold-boot repeat is complete with no workload intentionally running
   besides the probe.
2. Loaded Apple storage-driver versions and sanitized `ioreg` state are
   recorded in `docs/findings.md`.
3. Compare controller registers, ATA feature state, cache state, command order,
   and power state with the Linux captures.
4. Identify one material difference and test that difference alone on Linux.
5. Implement the smallest controller-, model-, or firmware-scoped correction.

The candidate must preserve Linux's existing `fsync()` durability contract. It
must not fake completion, silently suppress flushes, or globally change other
AHCI devices.

### Branch B: `F_FULLFSYNC` is also slow

This branch is not selected by the current measurement. Keep it as a fallback
only if a cold-boot repeat contradicts the first result and controlled checks
show the probe was not on the internal SSD.

Possible research may continue in two honest forms:

- an explicitly opt-in compatibility mode with weaker, macOS-like ordinary
  synchronization semantics and prominent durability warnings; or
- a storage-path bypass, such as macOS hosting a Linux VM or Linux placing
  write-heavy state on external/network storage.

The previous `barrier=0` experiment shows that suppressing barriers alone is
not sufficient: it weakened integrity and merely moved the same delay.

## Phase 2: Local Linux Fix Development

This phase started with a diagnostic-only patch after the Apple-versus-Linux
comparison identified interrupt mode as a concrete difference. The controlled
write comparison has now rejected MSI plus NCQ: it introduces 30-second queued
write timeouts and hard link resets instead of fixing the legacy flush tail.
The patch is not a production or submission candidate.

1. Build in a Linux VM or separate build machine; do not burden the test Mac
   with long kernel builds.
2. Use a maintained upstream kernel and reproduce the failure before patching.
3. Keep the working macOS system and establish a tested recovery path before
   any physical mutation; the current lab USB is not recovery media.
4. Scope the patch by PCI ID, DMI model, SSD model, and firmware only as tightly
   as the mechanism requires.
5. Run `scripts/checkpatch.pl`, build the affected subsystem, and boot the
   candidate side-by-side.
6. Compare the same bounded probe, block trace, package workload, suspend,
   cold boot, SMART state, and kernel log before and after.
7. Require an order-of-magnitude tail-latency improvement with no resets,
   corruption warnings, or durability deception.

The existing non-NCQ FUA patch is a negative result, not a starting patch. Do
not revive or submit it unless new evidence proves it would exercise a
different path from the runtime test.

The only remaining MSI configuration worth one guarded test is MSI plus forced
non-NCQ. That queue-depth-1 mode already passed read-only testing and removes
the command mode implicated by the writable failure. If it passes writes and
improves flush latency, compare it directly with legacy INTx plus non-NCQ and
treat it only as a possible compatibility path. If it faults or remains slow,
end the MSI performance branch. In parallel, trace actual legacy
`ATA_CMD_FLUSH_EXT` issue-to-completion time to locate the remaining 1.1-second
tail. Keep the upstream no-MSI default throughout.

## Phase 3: Upstream The Proven Fix

Once a local patch passes:

1. Rebase it onto the relevant maintainer tree or current upstream release.
2. Split unrelated storage, ACPI, graphics, and documentation changes.
3. Write a commit message containing the exact hardware match, observed failure,
   root cause, why the patch is safe, and sanitized before/after measurements.
4. Add `Fixes:` only when a specific introducing commit is actually known and
   `Cc: stable@vger.kernel.org` only when stable-kernel criteria are met.
5. Use the kernel's `scripts/get_maintainer.pl` for the current recipient list.
6. Send the patch as plain-text email, respond to review, revise in new versions,
   and retain all test evidence.
7. After upstream acceptance, request Ubuntu/Mint backports if needed.

The human author/submitted-by identity must be accurate. The user can obtain
real authorship by understanding the mechanism, directing and reviewing the
implementation, running or supervising the hardware tests, and signing the
Developer Certificate of Origin with a truthful `Signed-off-by`. Recheck the
kernel project's current policy on assisted code before submission and never
claim tests or authorship work that did not occur.

## Independent Contribution Tracks

### Apple ACPI `_GTF` compatibility

Linux rejected Apple's padded eight-byte representation of a seven-byte ATA
taskfile. Issuing the decoded command directly caused the SSD to reject it and
did not improve performance. A generic parser/diagnostic improvement could
still be an upstream contribution if it is spec-correct, safely bounded, and
tested beyond this one laptop. Do not present it as the latency fix.

### NVIDIA, Nouveau, and Apple GMUX

Do not begin by writing a new NVIDIA driver. Nouveau already supports the
Kepler-family GT 750M; the useful contribution would be a narrowly reproduced
bug in display updates, power management, suspend/resume, GPU switching, or
Apple GMUX integration.

Related work in
[`joaodriessen/macbookpro11-3-cachyos`](https://github.com/joaodriessen/macbookpro11-3-cachyos)
demonstrates a more controlled Intel-only architecture for this exact model:
boot a UKI through its EFI entry path, let upstream kernel `apple_set_os()`
keep the iGPU enabled, select Intel through `gpu-power-prefs`, and only then
change NVIDIA module policy. Upstream commits `71e49eccdca6` and
`4f90742d4a09` are the required baseline; Linux 6.8 contains neither complete
path.

Do not copy that repository's scripts directly. They contain hardcoded boot
values, overwrite the entire mkinitcpio `MODULES` list, and do not actually
prove the dGPU power rails are off. Reimplement discovery, backup, one-time
boot selection, exact EFI-variable verification, and rollback for the chosen
Ubuntu/Mint-compatible boot path.

First make storage non-blocking or run Linux from an independent storage path.
Then collect a clean graphics baseline with one kernel, one display stack, and
one GPU mode at a time. Prefer a preselected one-boot EFI/UKI state over a live
GPU handoff. Never repeat a live `vgaswitcheroo` handoff plus display-manager
restart without a tested recovery path. Measure actual PCI/GMUX power state;
module absence alone is not dGPU power-off. Upstream graphics work belongs in a
separate patch series and issue trail from AHCI storage work.

### Reproducer, tests, and diagnostics

Even if no safe performance patch exists, useful upstream work can include:

- a modern sanitized reproduction report for the unresolved old bug;
- better libata diagnostics around flush/FUA tail latency;
- regression tests or documentation for the `144d:1600` no-MSI quirk;
- a precise firmware-behavior report that prevents future false SSD-failure
  diagnoses.

These are legitimate contributions but must solve a reviewable upstream need,
not merely create a patch-shaped artifact.

## Stop Conditions

- Stop a strict storage patch if macOS `F_FULLFSYNC` proves equally slow and no
  new command or firmware mechanism exists.
- Stop any candidate that requires silent barrier removal or false completion.
- Stop if a test introduces ATA resets, filesystem warnings, boot loops, or an
  unrecoverable graphics handoff.
- Never repeat the rejected MSI-plus-NCQ writable profile merely to gather
  more samples; its three-reset failure is already decisive.
- Do not mix multiple kernel variables, drivers, or distributions in one test.
- Do not replace the SSD as a prerequisite for this project.

## Definition Of Success

Local success means a repeatably responsive Linux work environment on the
original hardware, with its durability trade-off stated exactly and a safe
recovery path. Upstream success means maintainers accept a technically correct,
generally useful contribution supported by reproducible evidence. Either can
be achieved without inventing an entirely new kernel or carrying a permanent
private fork.
