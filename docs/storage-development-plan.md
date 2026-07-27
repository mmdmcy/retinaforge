# Storage Development Plan

Last updated: 2026-07-18

Current status: paused. The temporary internal scratch partition has been
removed and full-size APFS restored and verified. No physical build, USB
provisioning, repartitioning, or reboot should occur without fresh explicit
authorization.

## What We Are Actually Trying To Build

The target already uses Linux's normal `ahci` and `libata` drivers. Enumeration,
ordinary transfers, interrupt delivery, SMART data, and the existing no-MSI
quirk work. The observed failure is narrower: after a dirty write, the SSD can
spend roughly 0.8 seconds completing the first durability or other serializing
operation.

Therefore, "develop a driver" means one of three scoped implementations. It
does not mean rewriting SATA, AHCI, filesystems, encryption, or the entire
kernel.

| Branch | What is built | Durability | Honest expected result |
| --- | --- | --- | --- |
| Strict controller fix | Small `ahci`/`libata` quirk for the proven missing initialization, state, or command sequence | Preserved | Fast and upstreamable only if the hardware has a fast strict path |
| Strict I/O shaping | Block-layer or device-mapper prototype that schedules ordinary I/O around real flushes | Preserved | Better interactivity, but each firmware flush may still take about 0.8 seconds |
| Relaxed compatibility mode | Opt-in device-mapper prototype that explicitly coalesces or defers selected durability requests | Weaker by design | Potentially macOS-like responsiveness with a documented crash-loss window |

The macOS `fsync()` versus `F_FULLFSYNC` experiment selected the strict
controller-fix branch. The physical Apple-versus-Linux comparison then found a
concrete controller difference worth isolating: Big Sur uses MSI with NCQ,
while stock Linux disables MSI through the historical `144d:1600` quirk. A
local opt-in patch tested only that difference. Read-only stages passed, but a
writable MSI-plus-NCQ stage produced three queued-write timeout/reset waves.
The patch is a negative diagnostic result, not a production fix.

## Repository Boundaries

This repository is the single public home for the tested `MacBookPro11,3`
work. Inside it, keep the storage track focused:

- sanitized storage evidence and deterministic reproducers;
- Linux kernel patch series that touch AHCI, libata, block I/O, or diagnostics;
- an out-of-tree storage prototype if experiments justify one;
- package/build instructions and rollback procedures for test kernels;
- upstream submission notes for storage maintainers.

Native Big Sur workstation material lives under `macos/`. NVIDIA/GMUX planning
lives under `docs/graphics/` and the graphics source notes. Do not mix graphics
driver experiments into AHCI/libata patch series. The CachyOS/Limine work is
useful graphics evidence, not evidence of an SSD fix. CachyOS still uses the
upstream Linux AHCI path unless it carries a relevant storage patch.

## Gate 1: Determine Whether Strict Persistence Can Be Fast

While Big Sur is working, run the prepared probe in
[`macos-fullfsync-test.md`](macos-fullfsync-test.md) from the internal APFS
volume and retain only sanitized aggregate results.

Initial result on 2026-07-17: ordinary `fsync()` mean 1.134 ms, strict
`F_FULLFSYNC` mean 6.863 ms, with 12 one-mebibyte samples in each mode. This
selects the strict controller-fix branch. A cold-boot repeat measured ordinary
`fsync()` mean 1.107 ms and strict `F_FULLFSYNC` mean 13.082 ms, confirming the
branch. A sanitized Apple state snapshot is recorded in `docs/findings.md`.
The next gate is a concrete Apple-versus-Linux state comparison.

### If `F_FULLFSYNC` is fast

Treat this as proof that Apple reaches a hardware state or sequence not yet
reproduced on Linux:

1. The cold-boot repeat is complete and confirms the result is stable.
2. Sanitized Apple driver, controller, cache, power, and command-state
   evidence is recorded; raw captures remain local and ignored.
3. Compare that state with Linux and identify exactly one material difference.
4. Reproduce only that difference in a temporary kernel branch.
5. Scope the patch as narrowly as evidence requires: PCI ID `144d:1600`, DMI
   `MacBookPro11,3`, SSD model, and firmware should not all be hardcoded unless
   each match is necessary.

The likely artifact is a small quirk in `drivers/ata/ahci.c`, a libata helper,
or the controller initialization path. The stock AHCI driver remains in place.

### Current MSI branch

The first physical diagnostic stage enabled MSI while forcing non-NCQ. It
passed a short read-only capture with one MSI vector, queue depth 1, handled
interrupts, and no ATA error, reset, or timeout. This is the first positive
local kernel result: the upstream blanket no-MSI behavior is not required for
that bounded configuration on this modern kernel.

The second stage also passed with MSI plus NCQ at queue depth 32. All four
bounded readers completed, 555 AHCI MSI interrupts were handled, the internal
SSD remained read-only, APFS remained unmounted, and no ATA fault was recorded.
This is a successful safety test of the historical failure combination, not a
durable-write speed benchmark.

The disposable write gate has now run. The stock legacy-INTx profile completed
without ATA faults but entered a roughly 1.1-second slow-flush state under the
heavier filesystem workload. The MSI-plus-NCQ profile failed during
`mkfs.ext4`: 13 queued writes timed out in the first wave, six in the second,
and three in the third, with a hard SATA link reset after each wave. Preserve
the upstream no-MSI behavior for writable NCQ.

One final, narrower MSI branch remains scientifically justified: MSI plus
forced non-NCQ at queue depth 1. It already passed read-only testing and
removes the command mode that timed out. Its second deterministic build was
canceled, the first output no longer exists, and no physical write run
occurred. Work is paused. If explicitly resumed, a clean writable pass with
materially lower flush latency would identify a possible compatibility
configuration, not a reason to enable MSI with NCQ. It must be compared against
legacy INTx plus non-NCQ before assigning causality. Any ATA fault or unchanged
slow tail ends the MSI branch.

### If `F_FULLFSYNC` is also slow

Record that no fast strict firmware operation is known. Do not label a skipped
or falsely completed flush as an AHCI fix. Move to Gate 2 and decide whether
Linux can be made usable through scheduling or an explicit compatibility
contract.

## Gate 2: Prove A Request Pattern Before Kernel Engineering

The previous `barrier=0` experiment weakened integrity and merely moved the
delay, so flush suppression alone is already rejected. Before writing a
device-mapper target, use a disposable test file or volume to replay bounded
request patterns:

1. dirty write, strict flush, then latency-sensitive read;
2. multiple dirty writes followed by one strict flush;
3. latency-sensitive reads before versus after the dirty-write epoch;
4. periodic real flushes at explicit intervals;
5. representative package-manager, SQLite, Git, browser, and journal patterns.

Measure p50, p95, p99, maximum latency, total throughput, and the number of
real device flushes. A candidate proceeds only if it improves interactive tail
latency rather than hiding the same 0.8-second wait elsewhere.

## Prototype A: Strict I/O Shaping

If request ordering improves responsiveness while retaining every durability
operation, prototype a block-layer policy or device-mapper target that:

- never acknowledges a flush before the device completes it;
- batches only ordinary requests where Linux semantics permit batching;
- prioritizes latency-sensitive reads before entering a known serialization
  point when ordering rules allow it;
- exports counters for queued writes, flush duration, and blocked requests;
- can be disabled at boot without changing the underlying filesystem.

This cannot promise fast `fsync()`. Its success criterion is that one process's
slow persistence request no longer makes unrelated desktop work unnecessarily
unresponsive.

## Prototype B: Explicit Relaxed Compatibility Mode

If strict shaping is insufficient but a macOS-like request pattern is useful,
prototype it first as an out-of-tree device-mapper target on a non-root test
volume. A possible design name is `dm-apple-sync`, but the name is provisional.

The prototype must:

- default to strict pass-through behavior;
- require an explicit option to enable relaxed behavior;
- state exactly which flush or FUA requests are coalesced or deferred;
- periodically issue a real device flush and expose the maximum dirty window;
- provide status counters and a command to force immediate persistence;
- warn that sudden power loss or a kernel crash can lose acknowledged data;
- never claim to preserve normal Linux `fsync()` semantics in relaxed mode;
- avoid the encrypted root volume until it is proven on disposable storage.

A shutdown or battery daemon may request a final flush, but it cannot turn a
relaxed mode into crash-safe storage. If the request-pattern tests show no
material gain, stop this branch instead of building a complicated workaround.

## Development Environment And Iteration Loop

Use the current powerful Linux computer or a VM for compilation. Keep the
MacBook as the hardware test target:

1. Clone the maintained upstream Linux tree outside this repository.
2. Reproduce the baseline on a current kernel containing all relevant Apple
   fixes before changing code.
3. Create one topic branch per hypothesis and keep the patch small.
4. Build side-by-side kernel packages or a UKI; do not overwrite the known-good
   kernel or recovery path.
5. Boot the candidate once, collect the same bounded measurements, and return
   to the stock entry on any reset, warning, boot failure, or regression.
6. Store source patches and sanitized summaries here, not full kernel trees,
   binaries, raw traces, UUIDs, serial numbers, or encryption metadata.

A GitHub fork of Linux can be used as a temporary collaboration/build branch,
but the intended deliverable is a small patch series against current upstream
Linux. Maintaining an entire private kernel fork is not the goal.

## Lab Topology And Codex Control

Use three deliberately different roles:

```text
current Linux workstation
  Codex, Git repository, research, kernel builds, package generation
                    |
                  SSH/SCP
                    |
Late-2013 MacBook Pro
  Big Sur reference ── optional Linux VM for ordinary Linux work
                    |
             reboot when authorized
                    |
  bare-metal Linux test environment using the physical AHCI controller
```

### Primary control machine

Keep Codex and the main Git checkout on the current Linux workstation. It is
already the stronger build and control machine. From there Codex can:

- edit and review the repository;
- build kernels and out-of-tree modules without heating the MacBook;
- copy source, packages, UKIs, probes, and sanitized results over SSH;
- operate the MacBook remotely while either macOS or bare-metal Linux is
  running;
- retain the investigation even while the MacBook is rebooting or offline.

Codex does not need to be installed on Big Sur for this workflow. Avoid having
two independent agents modify the same branch or machine at the same time.

### Big Sur reference system

Keep Big Sur intact as the known-good firmware, thermal, and performance
reference. Enable macOS Remote Login for one dedicated user and use SSH keys.
This permits the control machine to build and run the macOS full-sync probe,
collect sanitized state, and transfer files without installing a development
agent on the old host OS.

Do not expose SSH directly to the public internet. Restrict it to the trusted
LAN or a private VPN, and do not grant blanket unattended root access on the
daily-use macOS installation.

### Optional Linux VM

A Linux VM on Big Sur is useful for ordinary Linux work, package experiments,
and verifying that scripts build in the chosen distribution. It is optional
because the current Linux workstation can already perform those jobs.

The VM cannot validate an AHCI/libata fix. It sees a virtual controller and a
virtual disk image rather than PCI device `144d:1600` and the original SSD
firmware. Installing Codex inside the VM is therefore optional convenience,
not a way to test the storage bug. If Codex is installed there, use a separate
checkout or Git worktree and connect through SSH; do not share one writable
working tree between macOS and the guest.

For this Intel MacBook, start conservatively with an x86-64 Ubuntu or Debian
guest, hardware virtualization, four virtual CPUs, 8 GB RAM, and a sparse
64-100 GB virtual disk. Adjust only after checking host memory pressure and
temperatures. Mint Cinnamon can be used for daily work, but a minimal Ubuntu or
Debian guest is simpler for reproducible kernel builds.

### Bare-metal Linux test environment

The real driver test must boot Linux directly on the MacBook. Prefer a separate
Linux boot device while preserving the macOS installation and a tested recovery
route.
Booting Linux externally still loads the AHCI driver for the internal
controller, which is enough for read-only state captures and safe command
latency probes. Real filesystem workloads against the internal SSD require a
dedicated disposable internal test partition created only after a verified
backup.

The former recovery-bootstrap USB was already repurposed with explicit
permission as the `MBP_AHCI` lab medium. Its last recorded profile is the
rejected MSI-plus-NCQ writable diagnostic. Before another physical write test,
create and verify a recovery route and deliberately reprovision the lab USB.
Do not test destructive writes against the APFS container or working macOS
volume.

The first stage is intentionally smaller than a Linux distribution: the
external appliance in
[`native-readonly-baseline.md`](native-readonly-baseline.md) boots the current
upstream kernel, makes every non-lab block device read-only, collects the
sanitized controller state, and powers off. It needs no VM, network, SSH,
internal boot entry, or Linux filesystem. Only after that comparison selects a
specific mechanism should the project create a persistent external test
system or a disposable test volume for write workloads.

The bare-metal test image should have:

- key-based SSH enabled at boot on the trusted LAN;
- a non-root test account with narrowly configured `sudo`;
- the stock kernel plus one side-by-side candidate kernel;
- predictable network configuration and copied recovery instructions;
- no LUKS prompt for the disposable test system unless remote unlocking and
  recovery have first been deliberately implemented;
- a local timeout or rollback plan before unattended reboot experiments.

### Control rule

Compilation, source changes, and static analysis may run unattended on the
control machine. A reboot, bootloader change, partition change, firmware/NVRAM
write, raw-disk write, or first test of a new kernel remains a separately
authorized hardware step. Once one-boot selection, SSH recovery, and rollback
are proven, repeated bounded measurements can be automated safely.

## Validation Matrix

Every candidate must be compared with the same stock kernel and workload:

- cold boot and warm boot;
- encrypted and unencrypted disposable test volumes where applicable;
- bounded `fdatasync()`/flush probe and block trace;
- package installation, Git operations, SQLite commits, browser profile I/O,
  and ordinary desktop reads during writes;
- suspend/resume and shutdown;
- kernel log, ATA resets, filesystem warnings, SMART state, and thermals;
- abrupt-power-loss testing only on an expendable filesystem with verified
  backups, never on the working root volume.

For strict patches, durability must be preserved and tail latency must improve
by at least an order of magnitude. For relaxed mode, performance and the exact
data-loss window must both be reported; users must be able to choose strict
mode without recompiling.

## Upstream Route

When a local mechanism is proven:

1. Rebase it onto the relevant current maintainer tree.
2. Separate AHCI/libata, block-layer, diagnostics, and documentation changes.
3. Add a minimal reproducer and sanitized before/after evidence.
4. Run the kernel style and subsystem build checks.
5. Obtain the current recipient list with `scripts/get_maintainer.pl`.
6. Submit a plain-text patch series with truthful authorship, testing, and
   `Signed-off-by` information, then revise it through review.

A controller initialization correction could belong in AHCI/libata. A generic
strict scheduler improvement may belong in the block layer. A machine-specific
relaxed mode is much less likely to be accepted upstream and may remain an
external experimental module. These are different outcomes and should not be
presented as interchangeable.

## Immediate Order Of Work

1. Preserve the working Big Sur installation: complete. Recreate and verify
   external recovery media before any future destructive work.
2. Run and cold-boot-repeat the macOS strict-sync discriminator: complete.
3. Build and host-validate an authenticated current-upstream read-only
   appliance: complete for Linux `7.1.3`.
4. Capture the stock physical Linux state without mounting APFS: complete;
   legacy INTx confirmed.
5. Test the selected interrupt-mode difference with the smallest opt-in patch:
   complete for reads; MSI plus non-NCQ and bounded MSI plus NCQ both passed.
6. Run the gated disposable internal-SSD legacy-INTx versus MSI durability
   comparison: complete; writable MSI plus NCQ failed with three timeout/reset
   waves and is rejected.
7. Paused before physical MSI-plus-forced-non-NCQ testing. If work resumes,
   collect actual legacy ATA flush issue-to-completion timing first; it is the
   safer, higher-value discriminator. Run the MSI queue-depth-1 branch only
   after fresh authorization, deterministic rebuilds, scratch recreation, and
   full safety QA. Stop on any fault or absent latency improvement.
8. Convert only a proven mechanism into a production patch, then validate
   repeated boots, stress, errors, suspend, recovery, and tail latency.
9. Start the separate graphics repository only after storage no longer blocks
   meaningful Linux testing.
