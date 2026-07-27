# Experiment Plan

Status on 2026-07-25: storage-only research has resumed, but physical work
remains gated. The temporary scratch partition has been removed; APFS fills the
internal SSD and passed disk and volume verification. A stock legacy-INTx
command-trace artifact is ready, while NVIDIA/GMUX remains deferred. Do not
repartition, provision removable media, reboot the target, or run a physical
write test without the user-present authorization checkpoints in stage 15.
Baseline, NCQ, FUA, cache-mode, power-management, interrupt, raw ATA opcode,
non-NCQ FUA, and barrier experiments are complete.
The side-by-side non-NCQ FUA kernel was rejected before installation because a
runtime test exercised the same command path and retained unusable latency.
Linux Mint has since been erased and Big Sur `11.7.11` is working from the
internal SSD. The macOS strict-sync discriminator and its cold-boot repeat are
complete. The physical current-upstream comparison identified interrupt mode
as one concrete difference: Big Sur uses MSI with NCQ, while stock Linux
applies the historical `144d:1600` no-MSI quirk and uses legacy INTx.

An authenticated upstream Linux `7.1.3` read-only appliance completed its
physical baseline. An opt-in, DMI- and PCI-scoped MSI diagnostic then passed
both physical read-only stages: first with NCQ disabled, then with MSI plus NCQ
queue depth 32 and bounded concurrent reads. No stage mounted APFS or installed
Linux internally. A stock legacy-INTx disposable write probe passed, and the
heavier legacy filesystem-stack run reproduced roughly 1.1-second flush tails
without ATA faults. The matching MSI-plus-NCQ filesystem-stack run failed with
three queued-write timeout waves and three hard SATA link resets. That branch
is complete and rejected.

## Acceptance criteria

A change is accepted only when all of the following improve:

- no sustained desktop-wide I/O stalls during an ordinary write workload;
- lower tail block-request latency in the trace;
- application and package-manager responsiveness remains usable;
- the machine still boots with a documented recovery entry;
- SMART and kernel logs show no new storage errors.

## Sequence

### 1. Baseline trace

Capture a sanitized controller state plus block request latency while running a
small, bounded write workload. Do not run destructive or multi-gigabyte root
filesystem benchmarks.

The current target has a manual `libata.force=noncq` override in addition to
the upstream no-MSI quirk for PCI ID `144d:1600`. Capture this configuration as
the explicit baseline; do not treat it as a neutral default.

### 2. Restore the upstream NCQ configuration (complete)

At a user-present checkpoint, boot a one-time entry that omits only
`libata.force=noncq`. Keep the same kernel, filesystem, encryption, queue
settings, and upstream no-MSI controller quirk. Compare the bounded probe and
normal package/write workload directly with the baseline.

This did not pass. NCQ remained error-free but made the 16 MiB probe worse:
99.359 seconds versus 42.052 seconds with forced non-NCQ. NCQ plus FUA improved
the result to 32.666 seconds, but that is still unusable.

#### Completed failure isolation

- No NCQ ATA timeout or reset occurred, so queue-depth stepping was not the
  relevant branch.
- Hardware write-through mode made performance worse and was restored.
- IRQ 16 arrives normally. A 1 MiB write completes in about 1.5 ms; the final
  4 KiB FUA write takes about 832 ms.
- Raw `E7h` and `EAh` flush commands both stall. A 4 KiB pre-read only moves
  the same delay into the read and is rejected as a solution.

### 3. Runtime profile experiments (complete)

Tested one change at a time:

1. `max_performance` SATA link power policy: no improvement.
2. Hardware cache write-through: substantial regression.
3. A background 4 KiB read stream: no improvement to normal `fdatasync()`.

### 4. Boot-time controller experiments (complete for current hypothesis)

Disabling PCIe ASPM and forcing maximum-performance SATA link power did not
improve the bounded probe. Both are ruled out as the storage root cause.

### 5. Model-scoped non-NCQ FUA quirk (complete, rejected)

The prototype matches `APPLE SSD SM1024F` firmware `UXM6JA1Q` and permits FUA
while NCQ is disabled. A runtime queue-depth-1/FUA-on state exercised the same
Linux `WRITE DMA FUA EXT` path: 4 MiB took 6.792 seconds, median sync latency
was 860 ms, and maximum latency was 2,565 ms. The full kernel build was stopped
and nothing was installed.

### 6. Barrier suppression (complete, rejected)

Ext4 barriers were disabled only long enough for a bounded trace. Sync latency
remained 770-912 ms, and the trace moved about 755 ms into the ordinary data
write. The setting weakens crash guarantees and did not make the device usable,
so barriers were restored.

### 7. Apple-driver comparison (complete)

Apple's signed `AppleAHCIPort` and `IOAHCIBlockStorage` binaries were extracted
from an official Mojave update and disassembled. The exact `144d:1600` branch
only sets registry metadata. The block driver uses the same `E7h`/`EAh` flush
and NCQ FUA commands already measured as slow; ordinary writes omit FUA unless
explicitly requested. No new strict-durability command sequence was found, so
another controller patch is not justified.

### 8. Usable-system architecture

Choose and validate one path that does not require replacing the SSD:

1. an explicitly relaxed bare-metal mode matching ordinary macOS drive-cache
   semantics, with the durability loss documented and mitigated by battery
   monitoring and backups;
2. macOS controlling the SSD with Linux in a VM;
3. Linux using external or network-backed storage for write-heavy state.

A distro or filesystem reinstall is an experiment only if it has a distinct,
measurable storage-path hypothesis.

### 9. macOS strict-sync discriminator (complete)

Before ending bare-metal driver research, measure ordinary `fsync()` and
`F_FULLFSYNC` on this exact SSD under macOS. This was completed on the clean
Big Sur system without repartitioning or reinstalling anything.

Both the initial and cold-boot runs showed millisecond-scale strict
`F_FULLFSYNC`; the sanitized Apple state is recorded in `docs/findings.md`.
The next gate is to capture comparable Linux state and identify one concrete
state or ordering difference before writing a patch.

### 10. Current upstream read-only Linux state capture (complete)

Use the external-only appliance in
[`native-readonly-baseline.md`](native-readonly-baseline.md) to boot signed
upstream stable Linux `7.1.3` against the physical controller without
installing Linux or mounting APFS.

The source, deterministic build, standalone GRUB path, embedded initramfs,
read-only block guards, report checksums, FAT filesystem, automatic poweroff,
and internal-disk writer refusal have passed on the build host under OVMF with
a synthetic `APPLE SSD SM1024F` target. That test validates the harness, not
the Apple controller behavior.

The physical run was accepted after its report proved the internal disk was
read-only, only the labelled lab USB was mounted as a block filesystem, the
expected controller and SSD were found, the report checksum passes, and the
MacBook returned to Big Sur after removing the USB. It confirmed that stock
Linux applies the no-MSI quirk and uses legacy INTx on the real controller.

### 11. Opt-in MSI with non-NCQ (complete, passed)

Boot the DMI- and PCI-scoped diagnostic patch with
`ahci.mbp11_3_msi_diagnostic=1` and `libata.force=noncq`. Keep the internal SSD
read-only and run only the capture workload.

The physical run reported one MSI vector, queue depth 1, and handled AHCI
interrupts. It completed without an ATA exception, failed command, reset, I/O
error, or timeout, then powered off automatically. This establishes a safe
bounded MSI-plus-non-NCQ foothold on a modern kernel. It does not test write or
flush performance.

### 12. Opt-in MSI with NCQ and bounded reads (complete, passed)

Remove only `libata.force=noncq`, retaining the same kernel patch, read-only
guards, capture path, and automatic poweroff. Require MSI enabled, queue depth
32, completion of four concurrent bounded direct-read workers, valid report
checksums, and no ATA timeout, reset, or I/O error.

This is the historically risky combination that motivated the upstream quirk.
The physical run passed at queue depth 32: all four readers completed, 555 AHCI
MSI interrupts were handled, checksums passed, and no ATA fault was recorded.
Modern Linux can therefore sustain this short MSI-plus-NCQ read-only workload
on the exact machine. This still does not establish a latency fix.

### 13. Disposable legacy-INTx versus MSI write comparison (complete, MSI rejected)

Only after stage 12 passes and a current backup exists, create explicitly
disposable internal test space and compare the same bounded durability probe
under stock legacy INTx and diagnostic MSI. Keep kernel, NCQ state, request
size, cache policy, and workload identical. The test must target the internal
Apple SSD because an external virtual or USB disk does not exercise its
firmware path.

Proceed toward a production quirk only if MSI cuts durable-write tail latency
substantially and repeated cold/warm boots, stress, logs, and recovery checks
remain clean. Otherwise reject MSI as the performance mechanism and select the
next single observed state difference.

The stock legacy-INTx run completed the full plain-ext4 and dm-crypt-plus-ext4
stack without ATA errors. It nevertheless exposed repeated roughly 1.1-second
flush tails after sustained filesystem activity. The MSI run had one active
MSI vector and queue depth 32, but `mkfs.ext4` triggered three successive
30-second `WRITE FPDMA QUEUED` timeout waves. Error handling reset the SATA link
three times; the watchdog then reported `fail-mkfs`, and dm-crypt was not run.
The safety guards restored the SSD and every partition to read-only state and
APFS was never mounted.

This is a hard rejection of MSI plus NCQ for writable use on the target. Keep
the upstream no-MSI default. The read-only MSI-plus-NCQ pass is retained as a
useful negative lesson: bounded reads did not exercise the failure mechanism.

### 14. MSI plus forced non-NCQ disposable write test (unrun and paused)

If research is explicitly resumed, one final MSI branch could use
`libata.force=noncq`, require queue depth 1 and
exactly one MSI vector, and reuse the same guarded disposable partition. This
changes the command mode that failed while retaining the interrupt state that
differs from Big Sur. The combination already passed a bounded read-only
physical test.

Use the same plain-ext4 and dm-crypt-plus-ext4 workload and libata/block
tracepoints. Abort immediately on an ATA exception, timeout, reset, failed
command, filesystem warning, failed readback, failed read-only fsck, or loss of
the scratch-only write boundary. A pass would establish only a potential
queue-depth-1 compatibility path; it would not justify enabling MSI with NCQ
or replacing the generic upstream quirk. It must then be compared with legacy
INTx plus non-NCQ before attributing any latency change to MSI.

### 15. Legacy command-issue timing (artifact ready; physical run pending)

Repeat the exact current-upstream legacy filesystem workload with
`libata:ata_qc_issue` and completion tracepoints. Pair each actual
`ATA_CMD_FLUSH_EXT` issue and completion, rather than relying only on block
request timing. This determines whether the roughly 1.1-second tail is libata
queue delay before command issue or controller/device execution after issue.
That distinction decides whether the next code belongs in libata scheduling,
AHCI controller handling, or neither.

The storage-only appliance for this stage was rebuilt on 2026-07-24 from
authenticated upstream Linux `7.1.3` without an AHCI patch. It requires the
block issue/completion and libata issue/completion/failure tracepoints, uses the
monotonic trace clock, reserves a 32 MiB trace buffer, and fails the run if an
ATA flush was not observed or if the trace buffer overflowed. An offline
analyzer now reports:

- physical block-flush end-to-end time;
- block-flush issue to ATA flush issue time;
- ATA flush issue to completion time;
- failed and unmatched flush commands.

Two clean builds in separate output trees were byte-identical. The EFI loader
SHA-256 is
`d2888d105727f622f34bb174e3cdf14e2aaa56a3e7e792bcea6bfdbe921a6f93`;
the kernel SHA-256 is
`253073e46d876c289bfafd1f3cdfa021bdac6f9634a912deed6390c0ddc5d5a8`.
OVMF negative tests proved that the appliance powers off with a checksummed
refusal on the wrong DMI and, with exact target DMI plus SSD model, refuses the
current no-scratch layout. The synthetic target image remained byte-identical.

No USB has been provisioned and no physical disk has been changed. The real
run still requires a current backup, explicit authorization, and recreation of
the isolated final `MBPTEST` scratch partition from macOS.
