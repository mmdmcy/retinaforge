# Apple AHCI Linux Workbench For MacBookPro11,3 And SM1024F

An open, reproducible workbench investigating severe Linux write-latency
stalls on one tested hardware combination:

| Component | Tested target |
| --- | --- |
| Apple model identifier | `MacBookPro11,3` |
| Product | 15-inch Retina MacBook Pro, Late 2013 |
| Internal storage | 1 TB `APPLE SSD SM1024F`, firmware `UXM6JA1Q` |
| Storage controller | Apple/Samsung PCIe AHCI, PCI ID `144d:1600` |
| Graphics configuration | Intel Iris Pro and NVIDIA GeForce GT 750M |
| Known-good comparison OS | macOS Big Sur `11.7.11` |

This is an investigation, not a completed solution. No safe production Linux
fix has been confirmed. Results must not be generalized to every MacBook,
every 2013 MacBook Pro, every `MacBookPro11,x` variant, every Apple SSD, or
every controller carrying a related AHCI identifier.

The project starts with Ubuntu and Linux Mint because they provide a stable
kernel and packaging baseline. Debian, Fedora, and Arch can use the same
reproduction and validation harness later; changing distributions alone is not
assumed to change the underlying `ahci` driver path.

Project status on 2026-07-25: storage-only research has resumed, while
NVIDIA/GMUX work remains deferred. The test Mac is on Big Sur `11.7.11`; APFS
fills the internal SSD and no custom Linux kernel is installed internally. A
reproducible stock legacy-INTx command-trace artifact is ready for the next
measurement, but no USB has been reprovisioned and the Mac has no disposable
scratch partition. The 128 GB lab medium still holds the rejected
MSI-plus-NCQ writable diagnostic, not macOS recovery or a normal Linux
installer, and must not be booted casually.

## Goal

Determine whether this exact failure has a narrow, safe Linux fix that could
later be evaluated on separately identified affected machines:

- bounded storage latency during ordinary application writes;
- no desktop-wide freezes while package managers or journals write;
- a supported, updateable Ubuntu/Mint kernel path;
- controller-specific configuration or kernel quirks that are explicit,
  reproducible, and reversible.

## Confirmed first-target failure mode

The first Apple/Samsung controller exposes a standard AHCI interface. Linux
6.8 testing produced roughly 0.8-10 second durability stalls; authenticated
upstream Linux 7.1.3 is materially better in a light raw probe, but a sustained
filesystem workload still produces repeated roughly 1.1-second flush tails
under the stock legacy-INTx quirk. Generic SMART health remains clean, ordinary
data writes are fast, and that legacy path records no ATA timeout or reset.
Big Sur completes strict `F_FULLFSYNC` in milliseconds on the same SSD, so the
missing cross-OS difference remains an active investigation.

This repository does not assume a failing SSD, does not disable filesystem
integrity guarantees as a default, and does not treat a new Linux distribution
as a fix until it demonstrates a different result.

## Repository layout

- `scripts/collect-controller-state.sh` — sanitized controller-state capture.
- `scripts/prepare-kernel-source.sh` — fetch and authenticate the exact signed
  upstream stable tag used by the native baseline.
- `scripts/build-readonly-baseline.sh` — build the deterministic external-only
  Linux/GRUB capture appliance.
- `scripts/build-msi-diagnostic.sh` — build the opt-in MSI diagnostic variants
  used by the staged physical tests.
- `scripts/write-readonly-baseline-usb.sh` — provision an explicitly selected
  removable USB with destructive-operation guards and read-back verification.
- `scripts/run-latency-probe.sh` — bounded `fdatasync()` latency probe with
  optional block trace capture.
- `scripts/summarize-block-trace.py` — summarize flush-like block request
  latency from a local, ignored ftrace capture.
- `docs/architecture.md` — the storage-path model and boundaries.
- `docs/experiment-plan.md` — the staged validation and patch plan.
- `docs/findings.md` — public technical findings, measurements, negative
  results, and the strict macOS discriminator result.
- `docs/macos-fullfsync-test.md` — the decisive macOS benchmark procedure.
- `docs/linux-driver-upstream-roadmap.md` — local-fix-first driver development,
  validation, authorship, and upstream submission plan.
- `docs/storage-development-plan.md` — what would actually be built, where it
  sits in the Linux I/O path, and the evidence gate for each implementation.
- `docs/native-readonly-baseline.md` — build, safety, physical boot, recovery,
  and state-comparison procedure for the first current upstream capture.
- `patches/` — diagnostic, proposed, and validated kernel patches, with each
  artifact's status documented separately.

## Exact First Target

The first and currently only physically validated target is the
`MacBookPro11,3` and `APPLE SSD SM1024F` combination listed above. Historical
reproduction used Ubuntu 24.04 / Linux Mint kernel `6.8.0-134-generic`; the
new read-only baseline uses authenticated upstream stable Linux `7.1.3`
without installing a distribution or touching APFS.

No raw machine captures belong in this repository. The collector redacts serial
numbers by default; keep full captures locally under an ignored directory.

## Current evidence

The first target matches an existing upstream AHCI quirk for PCI ID
`144d:1600`: Linux disables MSI for this Apple/Samsung controller because NCQ
timed out with MSI enabled on older kernels. The stock upstream baseline uses
legacy INTx, while Big Sur reports MSI enabled and NCQ queue depth 32.

The first target exactly matches
[Red Hat Bug 1271863](https://bugzilla.redhat.com/show_bug.cgi?id=1271863),
which was closed for Fedora 22 end-of-life rather than fixed. Local traces and
direct ATA probes reproduce the unresolved command latency. NCQ, non-NCQ FUA,
both flush opcodes, cache write-through, power management, and barrier
suppression have all failed acceptance testing.

An external-only diagnostic kernel carries a DMI- and PCI-scoped opt-in that
clears only the existing no-MSI flag. Read-only MSI tests passed with NCQ both
disabled and enabled. The first filesystem-write test then reproduced the
reason for the upstream quirk: with MSI and queue depth 32, queued writes timed
out in three 30-second waves and forced three SATA link resets before the guard
aborted `mkfs.ext4`. MSI plus NCQ is therefore rejected as a production or
performance fix. APFS was never mounted, writes were confined to the explicit
disposable partition, and the internal disk was read-only again after the
probe. Nothing has been installed as a Linux system on the internal disk.

The current next step is storage-only and does not use the MSI patch: a
byte-reproducible stock Linux `7.1.3` legacy-INTx appliance is ready to split
filesystem flush latency into time before ATA command issue and time from ATA
issue to completion. Its host-side safety tests pass, but no USB has been
provisioned and the physical run remains pending because the restored APFS-only
disk layout has no disposable scratch partition. NVIDIA work is deferred until
storage is usable.

See [the public findings](docs/findings.md) for the decision record and
[the test protocol](docs/test-protocol.md) for the bounded, non-destructive
validation procedure.

## Publication boundary

This repository is structured to be safe for eventual public release. Commit
source code, sanitized technical findings, reproducible test procedures, and
primary-source notes. Keep the following local and ignored:

- raw traces, hardware dumps, logs, crash data, and complete command output;
- hostnames, IP addresses, disk serials, UUIDs, encryption metadata, and SSH
  state;
- assistant/session handoffs, conversation history, and machine-specific
  recovery diaries;
- proprietary Apple images, extracted binaries, kernel source/build trees, and
  package artifacts;
- rejected code prototypes that failed their motivating experiment.

Publish aggregate measurements and the smallest evidence needed to reproduce a
claim. Never commit a raw capture merely because it appears harmless.

## Safety rules

1. One controller or kernel variable changes per experiment.
2. Keep a known-good kernel boot entry before testing a new one.
3. Never use a destructive benchmark against the root filesystem.
4. Do not publish hostnames, IP addresses, serial numbers, encryption metadata,
   private logs, or raw conversation transcripts.
5. A proposed solution is not accepted until it improves measured tail latency
   and real desktop responsiveness.

## Status

The generic tuning and Apple-driver comparison phases are complete. Big Sur
`11.7.11` is installed on the first target and is cool and responsive in
ordinary use. The internal-APFS macOS probe measured mean `fsync()` latency of
1.134 ms and mean `F_FULLFSYNC` latency of 6.863 ms across 12 one-mebibyte
writes. A cold-boot repeat measured 1.107 ms and 13.082 ms respectively, with
no workload intentionally running besides the probe. Strict persistence is
therefore fast on macOS, reopening a narrow Linux AHCI/libata investigation.

The authenticated Linux `7.1.3` appliance completed its physical stock-kernel
baseline, confirming legacy INTx on the real controller. A light raw
legacy-INTx write/flush probe passed, but the heavier ext4 and dm-crypt stack
workload exposed repeated roughly 1.1-second flush tails without ATA faults.
The modified read-only MSI stages passed with non-NCQ and with bounded NCQ
reads, but the MSI-plus-NCQ filesystem-write stage failed with queued-write
timeouts and link resets. This validates the existing upstream no-MSI quirk
for writes on this exact machine.

The queue-depth-1 MSI-plus-forced-non-NCQ branch was prepared but its second
deterministic build was canceled, its first output no longer exists, and no
physical run occurred. It is not the next experiment. Storage-only work
resumed with a lower-risk, traced stock legacy run that distinguishes libata
queue delay from actual `FLUSH CACHE EXT` execution. The artifact passed
deterministic build and host-side guard QA; USB provisioning, scratch
recreation, and the physical run remain separate user-present checkpoints.
Storage remains separate from any later NVIDIA/GMUX track.
