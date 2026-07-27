# 2026-07-12 Upstream AHCI Quirk Review

- Checked: 2026-07-12 Europe/Amsterdam
- Researcher: Codex
- Scope: Linux AHCI handling of Apple/Samsung PCI ID `144d:1600`.
- Status: exact Fedora and upstream reports reproduced; the model-scoped
  non-NCQ FUA hypothesis was tested at runtime and rejected.

## Questions

- Does an existing upstream behavior already provide the correct controller
  configuration?
- What is the smallest safe next experiment for the observed durable-write
  stalls?

## Source Register

| Source | Authority | Checked | Status | Notes |
| --- | --- | --- | --- | --- |
| [Linux `drivers/ata/ahci.c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/ata/ahci.c) | Upstream kernel source | 2026-07-12 | Current | Still matches Samsung `0x1600` to its no-MSI board configuration; the code comment documents NCQ timeouts when MSI is enabled. |
| Ubuntu `linux-source-6.8.0` 6.8.0-134.134 | Distribution kernel source | 2026-07-12 | Current for target | Contains the same PCI match and no-MSI behavior as upstream. |
| Linux `drivers/ata/libata-core.c` | Upstream kernel source | 2026-07-12 | Current | The FUA configuration path requires usable NCQ support; forced `noncq` changes durable-write behavior. |
| [Red Hat Bug 1271863](https://bugzilla.redhat.com/show_bug.cgi?id=1271863) | Fedora kernel report | 2026-07-12 | Exact match, unresolved | Same Mac model, SSD, firmware, IRQ mode, and I/O stalls; closed for Fedora 22 EOL rather than fixed. |
| [Linux kernel Bug 60731](https://bugzilla.kernel.org/show_bug.cgi?id=60731) | Upstream kernel report | 2026-07-12 | MSI fixed, flush issue unresolved | Documents the no-MSI merge and the remaining 1-2 second `fsync()` / slow `FLUSH CACHE EXT` behavior on `MacBookPro11,3`. |
| [Apple `fsync(2)` manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fsync.2.html) | Apple documentation | 2026-07-12 | Archived, directly relevant | Ordinary macOS `fsync()` need not force the drive's volatile cache to media; `F_FULLFSYNC` requests the stronger guarantee. |
| [Linux patch submission guide](https://docs.kernel.org/process/submitting-patches.html) | Upstream kernel documentation | 2026-07-12 | Current | Any future patch must be narrow, tested, signed off by its human submitter, and accurately disclose assisted work. |

## Product Implications

- The target already receives the upstream no-MSI controller quirk; a private
  fork is not the first or preferred fix.
- The manual `libata.force=noncq` parameter is a stronger intervention than
  the upstream quirk and is the first variable to test.
- The baseline trace shows flush-like requests taking seconds even though
  ordinary writes complete in milliseconds. That distinction makes the
  durable-write path, rather than raw link bandwidth, the immediate target.
- NCQ, FUA, write-through cache, ASPM, and SATA power tests all failed to make
  the machine usable. IRQ tracing shows normal interrupt delivery and an
  approximately 832 ms final 4 KiB durability command.
- Direct ATA tests show the first command after a dirty write absorbs roughly
  0.8 seconds; a pre-read only relocates the delay.
- The drive advertises non-NCQ `WRITE DMA FUA EXT`, but runtime queue-depth-1
  testing with FUA exposed retained 0.8-2.6 second sync latency. The proposed
  model-specific opt-in is rejected and was never installed.
- Disabling ext4 barriers also failed: it weakened durability and shifted the
  same approximately 0.8-second wait into an ordinary write.
- Apple's documented weaker ordinary `fsync()` semantics plausibly explain
  part of the macOS/Linux difference. This is an inference; the next research
  branch must inspect Apple's actual AHCI behavior before proposing code.

## Recheck Triggers

- The GRUB test without forced `noncq` still reproduces high durable-write
  latency.
- A current supported Ubuntu kernel shows different AHCI behavior.
- Apple AHCI source or a trace reveals a vendor-specific command sequence not
  covered by the completed ATA tests.
