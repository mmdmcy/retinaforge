# MacBookPro11,3 Retina Workbench

One open repository for the Late-2013 15-inch Retina MacBook Pro configuration
that is actually being tested. This is the centralized home for notes and
artifacts that used to live in separate local trees.

| Component | Tested target |
| --- | --- |
| Apple model identifier | `MacBookPro11,3` |
| Product | 15-inch Retina MacBook Pro, Late 2013 |
| CPU | Intel Core i7-4960HQ |
| Memory | 16 GB DDR3L |
| Graphics | Intel Iris Pro and NVIDIA GeForce GT 750M |
| Internal storage | 1 TB `APPLE SSD SM1024F`, firmware `UXM6JA1Q` |
| Storage controller | Apple/Samsung PCIe AHCI, PCI ID `144d:1600` |
| Known-good host OS | macOS Big Sur `11.7.11` |

Results must not be generalized to every 2013 MacBook Pro, every
`MacBookPro11,x` variant, every Apple SSD, or every related AHCI identifier.

## Tracks In This Repository

| Track | Status | Where |
| --- | --- | --- |
| Native Big Sur workstation | Working baseline | [`macos/`](macos/README.md) |
| Linux AHCI / SM1024F storage latency | Active investigation, no safe production fix | sections below plus `docs/`, `scripts/`, `patches/`, `tools/` |
| Linux Intel-first graphics / GMUX | **Active** — `force_igd` opens IGD/eDP but DRM modes stay 0; 08-01 UKI retest still negative (2026-08-13). Big Sur–style switching is not a Linux target on this mux. | [`docs/graphics/intel-first-repro.md`](docs/graphics/intel-first-repro.md), [`docs/graphics/why-not-macos-ags.md`](docs/graphics/why-not-macos-ags.md) |
| Windows Intel-first / GMUX | Archived evidence; no further implementation work | [`docs/archive/windows/`](docs/archive/windows/README.md) |

Private captures, recovery media, deal photos, raw traces, and build outputs
stay out of Git under the local RetinaForge `local-only/` hub.

Fleet SSH aliases for the lab laptop vs. the controller Mac are documented in
[`docs/fleet-naming.md`](docs/fleet-naming.md).

## Native Big Sur Workstation

Keep Big Sur as the stable host. Use MacPorts for maintained packages, compile
compatibility builds when needed, and treat Linux as a narrow service boundary
rather than the default desktop.

Start here:

- [`macos/README.md`](macos/README.md)
- [`macos/docs/modern-workstation-plan.md`](macos/docs/modern-workstation-plan.md)
- [`macos/docs/go-1.26.5-validation.md`](macos/docs/go-1.26.5-validation.md)
- [`macos/patches/go-1.26.5-big-sur.patch`](macos/patches/go-1.26.5-big-sur.patch)

```bash
sudo ./macos/scripts/bootstrap-big-sur-dev.sh
./macos/scripts/build-go-1.26.5-big-sur.sh
```

MacOS workstation material under `macos/` is BSD-3-Clause. The Go patch applies
to upstream Go source under Go's own BSD-style license.

## Linux Storage Workbench

An open, reproducible investigation of severe Linux write-latency stalls on the
exact `MacBookPro11,3` + `APPLE SSD SM1024F` combination above.

This is an investigation, not a completed solution. No safe production Linux
fix has been confirmed.

The project starts with Ubuntu and Linux Mint because they provide a stable
kernel and packaging baseline. Debian, Fedora, and Arch can use the same
reproduction and validation harness later; changing distributions alone is not
assumed to change the underlying `ahci` driver path.

Project status on 2026-07-30: the Windows GMUX route is archived and native
Linux is the active route. The test Mac retains Big Sur `11.7.11`; its Windows
partitions were removed and APFS was expanded, and no custom Linux kernel is
installed internally. Two clean builds of the tightened stock legacy-INTx
command-trace appliance were byte-identical and passed host validation. The
128 GB lab medium now contains that appliance on its FAT lab partition, with an
APFS data partition preserved separately. It is not macOS recovery or a normal
Linux installer and must not be booted casually. No disposable internal scratch
partition exists, so no physical Linux test has run.
See [`docs/linux-native-roadmap.md`](docs/linux-native-roadmap.md) for the
storage and graphics gates. For continuation on another host, start with the
[session handoff](docs/session-handoff.md).

### Storage goal

Determine whether this exact failure has a narrow, safe Linux fix that could
later be evaluated on separately identified affected machines:

- bounded storage latency during ordinary application writes;
- no desktop-wide freezes while package managers or journals write;
- a supported, updateable Ubuntu/Mint kernel path;
- controller-specific configuration or kernel quirks that are explicit,
  reproducible, and reversible.

### Confirmed first-target failure mode

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

### Storage layout

- `scripts/collect-controller-state.sh` — sanitized controller-state capture.
- `scripts/prepare-kernel-source.sh` — fetch and authenticate the exact signed
  upstream stable tag used by the native baseline.
- `scripts/build-readonly-baseline.sh` — build the deterministic external-only
  Linux/GRUB capture appliance.
- `scripts/build-msi-diagnostic.sh` — build the opt-in MSI diagnostic variants
  used by the staged physical tests.
- `scripts/write-readonly-baseline-usb.sh` — provision an explicitly selected
  removable USB with destructive-operation guards and read-back verification.
- `scripts/prepare-lab-backup-usb.sh` — erase an explicitly selected removable
  USB into a small Linux lab/report volume plus a separate APFS backup target.
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

No raw machine captures belong in this repository. The collector redacts serial
numbers by default; keep full captures locally under an ignored directory.

### Current evidence

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

The current next step is storage-only and does not use the MSI patch: rebuild a
stock Linux `7.1.3` legacy-INTx appliance after binding its guard to a newly
approved scratch partition. It will split filesystem flush latency into time
before ATA command issue and time from ATA issue to completion. Component,
analyzer, and synthetic filesystem tests pass, but the revised appliance has
not had its required complete build and virtual QA. No USB has been provisioned
and the current Big Sur plus Windows layout has no disposable scratch
partition. NVIDIA work is deferred until storage is usable.

See [the public findings](docs/findings.md) for the decision record and
[the test protocol](docs/test-protocol.md) for the bounded, non-destructive
validation procedure.

### Storage status

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
queue delay from actual `FLUSH CACHE EXT` execution. A historical artifact
passed deterministic build and host-side guard QA. The tightened replacement
must be rebuilt and revalidated; scratch creation, USB provisioning, and the
physical run remain separate user-present checkpoints.

## Linux Graphics Notes

Intel-first internal panel ownership was verified on this `MacBookPro11,3`
(2026-08-01): macOS-written Intel `gpu-power-prefs` plus an EFI-stub/UKI boot
so `apple_set_os()` runs, then `i915` owns eDP 2880×1800. A 2026-08-05
same-recipe retest did **not** restore Intel eDP ownership (Nouveau remained
primary); see the negative note before assuming the path still works without a
fresh check-script pass.

- [`docs/graphics/intel-first-repro.md`](docs/graphics/intel-first-repro.md)
- [`docs/graphics/README.md`](docs/graphics/README.md)
- Evidence (success):
  [`docs/source-notes/2026-08-01-intel-panel-and-display-path.md`](docs/source-notes/2026-08-01-intel-panel-and-display-path.md)
- Evidence (failed retest):
  [`docs/source-notes/2026-08-05-intel-panel-path-retest.md`](docs/source-notes/2026-08-05-intel-panel-path-retest.md)
- Investigation + Debian/Mint migration plan (2026-08-06):
  [`docs/source-notes/2026-08-06-intel-panel-investigation-and-migration.md`](docs/source-notes/2026-08-06-intel-panel-investigation-and-migration.md)

Keep graphics evidence and AHCI/libata patch series separate even though both
tracks share this repository.

## Publication boundary

This repository is structured for public release. Commit source code, sanitized
technical findings, reproducible test procedures, and primary-source notes.
Keep the following local and ignored:

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
6. Back up the machine and keep a known-good recovery route before compatibility
   builds or experimental kernels.

## License

- Linux storage/kernel workbench material at the repository root: GPL-2.0.
- Native Big Sur workstation material under [`macos/`](macos/): BSD-3-Clause
  ([`macos/LICENSE`](macos/LICENSE)).
- Third-party sources (Linux, Go) remain under their upstream licenses.
