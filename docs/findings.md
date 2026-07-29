# Public Technical Findings

Last updated: 2026-07-25

This document contains the sanitized engineering record suitable for public
review. Raw traces, serial numbers, UUIDs, network details, private operational
notes, proprietary binaries, and conversation history are intentionally absent.

## Target

- Apple model: `MacBookPro11,3`.
- Storage controller: Apple/Samsung PCIe AHCI, PCI ID `144d:1600`.
- SSD: `APPLE SSD SM1024F`, firmware `UXM6JA1Q`.
- Linux baseline: Ubuntu 24.04 / Linux Mint kernel `6.8.0-134-generic`.
- Linux root during testing: LUKS2 -> LVM -> ext4.

The controller used Linux's existing no-MSI quirk and legacy INTx. SMART data
was clean, the SATA link negotiated at 6 Gb/s over PCIe 5 GT/s x4, and the
observed stalls had no accompanying media, CRC, ATA timeout, or reset errors.

## Prior Reports

- [Red Hat Bug 1271863](https://bugzilla.redhat.com/show_bug.cgi?id=1271863)
  reports the same Mac model, SSD, firmware, IRQ mode, NCQ capability, and
  desktop-wide write stalls. It was closed because Fedora 22 reached end of
  life, not because the issue was fixed.
- [Linux kernel Bug 60731](https://bugzilla.kernel.org/show_bug.cgi?id=60731)
  documents the controller family. Disabling MSI addressed NCQ timeouts and
  became the upstream quirk, while later reports retained very slow durable
  writes and `FLUSH CACHE EXT` operations.

The current upstream no-MSI quirk solves a different failure class. It does not
solve the durable-write latency reproduced here.

## Bounded Linux Measurements

All probes used small temporary files and removed them afterward.

| Configuration | 16 MiB elapsed | Median sync | Maximum sync |
| --- | ---: | ---: | ---: |
| forced non-NCQ, FUA off | 42.052 s | 2,718 ms | 4,115 ms |
| NCQ, FUA off | 99.359 s | 6,055 ms | 10,464 ms |
| NCQ, FUA on | 32.666 s | 2,563 ms | 2,580 ms |
| NCQ/FUA, hardware cache write-through | 73.869 s | 4,168 ms | 15,017 ms |

Additional controlled results:

- Disabling PCIe ASPM did not improve latency.
- Forcing the SATA link power policy to `max_performance` did not improve it.
- Hardware write-through substantially worsened the result.
- Queue depth 1 with FUA still exposed completed a 4 MiB probe in 6.792 seconds,
  with 860 ms median and 2,565 ms maximum sync latency.
- Temporarily disabling ext4 barriers retained 770-912 ms sync latency and
  moved roughly 755 ms into an ordinary data write. Barriers were restored.
- A continuous background 4 KiB reader did not improve normal `fdatasync()`.

No tested queue, cache, FUA, barrier, scheduler, or power configuration met the
acceptance criteria.

## Current-Upstream Filesystem-Stack Result

Authenticated upstream Linux `7.1.3` materially improves the lightest test.
With the stock `144d:1600` no-MSI quirk, legacy INTx, NCQ queue depth 32, and a
disposable raw partition, 12 direct one-mebibyte write/flush/readback cycles
passed without an ATA fault. Median write latency was 1.222 ms and median flush
latency was 5.144 ms. Linux 7.1.3 contains
[`0ea84089dbf6`](https://github.com/torvalds/linux/commit/0ea84089dbf62a92dc7889c79e6b18fc89260808),
which avoids starvation of non-NCQ commands by queued NCQ work; Linux 6.8 does
not contain that change.

That light probe was not representative enough. An otherwise identical
physical run created ext4 directly on the disposable partition and then on an
ephemeral dm-crypt mapping. Both filesystems passed direct readback and
read-only `e2fsck`, APFS remained unmounted, and the log contained no ATA
timeout, reset, or failed command. The measured samples were:

| Current Linux 7.1.3 legacy-INTx profile | Median 1 MiB write | Median `fdatasync()` | Maximum measured `fdatasync()` |
| --- | ---: | ---: | ---: |
| plain ext4 | 1.038 ms | 11.671 ms | 12.327 ms |
| dm-crypt plus ext4 | 1.048 ms | 1.137 s | 1.154 s |

The encryption layer is not established as the cause. The block trace recorded
113 flush requests across setup, measured writes, unmount, and read-only fsck:
p50 18.021 ms, p95 1.133 s, and maximum 1.136 s. Repeated roughly 1.1-second
flushes also appeared in the plain-ext4 cleanup path after enough preceding
filesystem activity. The defensible conclusion is that a sustained workload
enters a slow-flush state that the small raw probe never reached. A legacy run
with libata command tracepoints is still needed to separate time spent waiting
to issue `FLUSH CACHE EXT` from time spent executing it on the controller.

## Command-Level Isolation

A block/IRQ trace showed:

- a 1 MiB ordinary data write completed in about 1.5 ms;
- the following 4 KiB synchronous/FUA write completed in about 832 ms;
- the expected legacy interrupt was delivered and handled normally.

Direct ATA pass-through tests showed:

- `FLUSH CACHE` (`E7h`) and `FLUSH CACHE EXT` (`EAh`) both converged near
  820 ms after a dirty write;
- a 4 KiB read before the flush moved roughly 796 ms of waiting into the read
  instead of removing it;
- a 512-byte read, `READ VERIFY EXT`, `CHECK POWER MODE`, and continuous small
  reads did not provide a usable alternative.

The device acknowledges ordinary writes quickly, then spends roughly 0.8
seconds serializing the first following durability or non-write operation. The
measured delay is not explained by lost interrupts, raw PCIe bandwidth, ext4,
dm-crypt CPU cost, or link power management.

## Rejected Prototype

The SSD advertises non-NCQ `WRITE DMA FUA EXT`. A model-and-firmware-scoped
prototype was drafted to expose that path while NCQ was disabled. Before any
custom kernel was installed, queue-depth control reproduced the same non-NCQ
FUA path at runtime and retained 0.8-2.6 second sync stalls.

The build was stopped. No custom kernel was installed, and the prototype is not
published as a candidate patch because its motivating hypothesis failed.

## Apple ACPI `_GTF`

Apple firmware returned an eight-byte representation of a seven-byte ATA
taskfile, which Linux rejected as an unexpected `_GTF` length. The decoded
command was issued directly as a controlled experiment. The SSD rejected it
with ATA `ABRT`, and latency did not improve.

This may justify independent ACPI parser or diagnostic work, but it is not the
storage-performance fix.

## Apple Driver Comparison

Signed `AppleAHCIPort` and `IOAHCIBlockStorage` binaries from an official Apple
update were inspected locally; the proprietary files are not distributed here.

- The exact `144d:1600` branch sets descriptive registry metadata but issues no
  private initialization command and programs no special controller register.
- Apple's strict cache synchronization uses standard ATA `E7h`/`EAh` flushes.
- Apple's NCQ write path can use standard FUA when explicitly requested.
- Ordinary non-NCQ writes use standard DMA commands without substituting
  `WRITE DMA FUA EXT`.

[Apple's `fsync(2)` documentation](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fsync.2.html)
states that ordinary `fsync()` need not force a drive's volatile cache to
physical media, while `F_FULLFSYNC` requests the stronger guarantee. This
provides a plausible semantics-based explanation for macOS responsiveness
without implying a hidden fast strict-durability command.

## Cross-OS Result And Strict-Sync Discriminator

The same internal SSD is cool and responsive under a clean Big Sur `11.7.11`
installation. This is strong evidence against treating physical SSD replacement
as the default diagnosis, but ordinary responsiveness does not establish strict
flush performance.

The prepared comparison was run on 2026-07-17 from the internal APFS Data
volume on Big Sur `11.7.11`. It performed 12 one-mebibyte writes in each mode;
the temporary files were removed after each mode.

| Mode | Mean sync | Median sync | P95 sync | Maximum sync |
| --- | ---: | ---: | ---: | ---: |
| ordinary `fsync()` | 1.134 ms | 1.094 ms | 1.560 ms | 1.560 ms |
| strict `F_FULLFSYNC` | 6.863 ms | 6.598 ms | 11.610 ms | 11.610 ms |

This is a decisive positive result for strict Linux investigation: macOS can
complete the stronger persistence operation in milliseconds on the same
internal SSD, while Linux previously observed roughly 0.8-second durability
stalls. The semantics-only explanation is rejected as sufficient. The exact
missing difference is still unknown; it may be controller state, cache state,
power state, command ordering, or another storage-stack interaction that the
static Apple-driver comparison did not expose.

The cold-boot repeat has now completed with no workload intentionally running
besides the probe. A sanitized Apple storage/controller snapshot is also
recorded below. The next step is to compare it with the Linux baseline. Do not
claim a driver fix until one concrete difference is reproduced on Linux.

A second identical run followed a full reboot, with no workload intentionally
running besides the probe:

| Mode | Mean sync | Median sync | P95 sync | Maximum sync |
| --- | ---: | ---: | ---: | ---: |
| ordinary `fsync()` | 1.107 ms | 1.087 ms | 1.300 ms | 1.300 ms |
| strict `F_FULLFSYNC` | 13.082 ms | 12.551 ms | 16.966 ms | 16.966 ms |

The result remains comfortably in the millisecond range after reboot.

### Initial Sanitized Apple Storage State

The cold-boot snapshot reported AppleAHCIPort `346.100.2`, IOAHCIFamily
`294.100.1`, and IOAHCIBlockStorage `332`. The internal PCIe SSD negotiated
PCIe 5.0 GT/s at x4 with TRIM and SMART verified. The IORegistry exposed the
AppleAHCI/AppleAHCIPort/AppleAHCIDiskDriver/IOAHCIBlockStorageDevice path.
Serials, UUIDs, and raw ioreg output remain local and ignored.

The sanitized state also reported NCQ enabled with queue depth 32, SATA
features value `62` (`0x3e`), AHCI port ALPM disabled, 64-bit addressing
enabled, 512-byte logical sectors, 4096-byte physical sectors, and low 32 bits
of AHCI capabilities equal to `0xc3349f80`. This rules out the simple theory
that macOS is fast merely because it disables NCQ or enables aggressive link
power management. The physical current-upstream Linux capture and staged MSI
diagnostic are summarized next.

## Current-Upstream MSI Diagnostic

The authenticated Linux `7.1.3` physical baseline confirmed the current
upstream behavior on this machine: the `144d:1600` no-MSI quirk selects legacy
INTx. The clearest material Apple-versus-Linux state difference is therefore
interrupt mode: Big Sur reports MSI enabled, whereas stock Linux disables it
for this controller because MSI plus NCQ timed out on historical kernels.

A local diagnostic patch adds an explicit boot-time opt-in scoped to both DMI
model `MacBookPro11,3` and PCI ID `144d:1600`. It clears only
`AHCI_HFLAG_NO_MSI`; it does not alter command handling, cache policy, APFS, or
the permanent upstream default.

The first physical stage booted that patch with NCQ disabled. It reported one
MSI vector, queue depth 1, and 53 handled AHCI interrupts, with no ATA
exception, failed command, hard reset, I/O error, or timeout. The internal SSD
was read-only, APFS was never mounted, and the appliance powered off
automatically. This is evidence that modern Linux can use MSI safely in a
short, bounded MSI-plus-non-NCQ run on this hardware.

The second physical stage also passed with MSI plus NCQ at queue depth 32. Four
concurrent direct-read workers transferred 256 MiB total in a bounded run; the
diagnostic completed successfully, 555 AHCI MSI interrupts were handled, and
the log contained no ATA timeout, reset, failed command, or I/O error. The SSD
and both internal partitions remained read-only, APFS was not mounted, capture
and artifact checksums passed, and the FAT USB passed a read-only filesystem
check afterward. This established only that bounded reads were safe.

The first writable MSI filesystem-stack run decisively failed. Linux 7.1.3
allocated one MSI vector on IRQ 36, enabled NCQ queue depth 32, and confined
writes to the exact disposable final partition. `mkfs.ext4` then encountered
three 30-second timeout waves:

| Timeout wave | Timed-out queued writes | Active NCQ mask | Recovery |
| --- | ---: | --- | --- |
| first | 13 | `0x3ffe0` | hard SATA link reset |
| second | 6 | `0xce800` | hard SATA link reset |
| third | 3 | `0x38` | hard SATA link reset |

Each wave reported `WRITE FPDMA QUEUED`, `Emask 0x4 (timeout)`, device status
`DRDY`, and no SATA link error bits. After each reset, a subset of the retried
commands completed immediately; after the third reset, the final retries and a
`FLUSH CACHE EXT` completed. The 60-second `mkfs.ext4` watchdog had already
sent `SIGKILL` while the process was blocked in I/O, so the probe correctly
reported `fail-mkfs` and did not proceed to dm-crypt. In total, 22 queued-write
commands were reported across the three waves and three hard resets occurred.

The safety envelope held: APFS was never mounted, only the disposable scratch
partition was writable during the probe, the SSD and all partitions were
read-only afterward, the capture checksum passed, and the FAT report volume
passed a read-only filesystem check. The incomplete scratch filesystem was
later removed after the research pause.

This result validates the upstream no-MSI quirk on the exact target for NCQ
writes. A short MSI read test cannot be used to infer writable safety. Do not
remove `AHCI_HFLAG_NO_MSI` for a production Linux installation, and do not
submit the current diagnostic as a fix. MSI with NCQ explicitly disabled was
prepared as one final queue-depth-1 compatibility branch, but its second
deterministic build was canceled and it was never physically run. It remains
an experiment, not a ready artifact or solution.

## Restored Daily-Driver State And Pause

After testing, the temporary 8.3 GB final partition was removed from macOS and
the adjacent APFS physical store was expanded from 992.0 GB to the remaining
disk. The final physical map contains only a 209.7 MB EFI partition and a 1.0
TB APFS container with capacity 1,000,345,825,280 bytes. The GPT partition map
and both the sealed system and Data APFS volumes passed read-only verification.

The target now runs Big Sur `11.7.11`; no Linux system or custom kernel is
installed internally. Storage-only research resumed on 2026-07-24, while
graphics work remains deferred. The highest-value safe next measurement is
libata issue-to-completion timing for actual flush commands on the legacy-INTx
stack. A deterministic, fail-closed artifact for that measurement is ready,
but no USB was provisioned and no physical test was run because the SSD
currently has no disposable scratch partition. Writable MSI plus NCQ must not
be repeated unchanged. The separate MSI-plus-forced-non-NCQ branch remains
unrun and is not the next test.

## Related `MacBookPro11,3` Graphics Work

The public
[`joaodriessen/macbookpro11-3-cachyos`](https://github.com/joaodriessen/macbookpro11-3-cachyos)
repository documents an Intel-only CachyOS/UKI/Limine configuration for the
same Mac model and Iris Pro/GT 750M layout. Its strongest contribution to this
workbench is a graphics architecture based on upstream Linux behavior:

1. chainload a UKI as an EFI application so the kernel EFI stub runs;
2. let upstream `apple_set_os()` keep the firmware-hidden iGPU enabled;
3. select the iGPU through Apple's `gpu-power-prefs` EFI variable;
4. verify Intel panel ownership before making driver policy persistent.

Upstream commit
[`71e49eccdca6`](https://github.com/torvalds/linux/commit/71e49eccdca6328eecc335ed8f5557bd0ed70fc6)
explicitly includes `MacBookPro11,3`. Linux 6.8 predates that support, and a
2025 follow-up added a fallback product-name lookup for Apple EFI firmware.
Future graphics testing should use a kernel containing both changes.

The reviewed repository does not address AHCI or identify an SSD, so it does
not weaken the storage findings. Its scripts are machine-specific and contain
hardcoded kernel/root values. They also conflate driver blacklisting with full
dGPU power-off even though their own D3cold investigation says the driverless
GPU remains powered. Reuse the upstream mechanism and recovery discipline, not
the scripts verbatim. See the
[complete source review](source-notes/2026-07-15-macbookpro11-3-cachyos-review.md).

The later Windows Set OS probe physically confirmed one part of that
architecture on this target. Iris Pro 5200 enumerated, loaded its existing
signed Intel driver, and reported no PnP problem when Windows was chainloaded
through rEFInd. NVIDIA remained the 2880x1800 panel owner and returned to P8.
Removing the USB and booting Windows directly restored NVIDIA-only enumeration.

Panel selection did not pass its verification gate. Windows reported successful
Apple `gpu-power-prefs` writes but denied runtime readback, so no Intel-panel
boot was attempted. An explicit dedicated recovery write followed by a direct
boot restored the known NVIDIA-only state. No GMUX power command was issued.

For future cooling work, Linux is technically closer to the macOS graphics
stack because upstream already coordinates Apple Set OS, `i915`, `apple-gmux`,
VGA switcheroo, and resume. The internal Apple SSD remains a separate blocker:
stock legacy INTx has long flush tails and MSI plus NCQ writes are rejected.
An external USB SSD may be useful only for a non-production graphics lab; it
does not satisfy the active goal of native Linux on the original internal SSD.

## Contribution Boundary

Storage, Apple ACPI, and NVIDIA/Nouveau/GMUX are separate upstream tracks. A
future patch must first pass locally, preserve its stated durability contract,
match hardware narrowly, retain a stock recovery path, and include sanitized
before/after evidence. See
[`linux-driver-upstream-roadmap.md`](linux-driver-upstream-roadmap.md).
