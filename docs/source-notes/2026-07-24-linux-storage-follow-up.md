# 2026-07-24 Linux Storage Follow-up

- Checked: `2026-07-24 Europe/Amsterdam`
- Researcher: `Codex`
- Scope: current upstream AHCI/libata state, applicability of the non-NCQ
  starvation fix, and the smallest safe discriminator for the remaining
  `MacBookPro11,3` flush tail.
- Status: no new upstream device quirk or ready-made fix found; command-level
  timing remains the next useful measurement.

## Questions

- Has upstream replaced or refined the Samsung `144d:1600` no-MSI quirk?
- Does current libata contain a change that already explains or fixes the
  sustained roughly 1.1-second flush tail?
- Can existing tracepoints distinguish Linux queueing delay from time after the
  ATA flush reaches the low-level AHCI driver?
- What would remain ambiguous after that trace?

## Source Register

| Source | Authority | Checked | Status | Notes |
| --- | --- | --- | --- | --- |
| [Linux `drivers/ata/ahci.c`](https://github.com/torvalds/linux/blob/master/drivers/ata/ahci.c) | Upstream kernel source | 2026-07-24 | Current | Samsung PCI device `0x1600` still selects `board_ahci_no_msi`; the comment still cites NCQ timeouts with MSI. |
| [Non-NCQ starvation fix `0ea84089dbf6`](https://github.com/torvalds/linux/commit/0ea84089dbf62a92dc7889c79e6b18fc89260808) | Upstream kernel commit | 2026-07-24 | Present in tested 7.1.3 | Holds a deferred non-NCQ command while NCQ drains instead of repeatedly requeueing it behind new NCQ traffic. |
| [Linux libata trace events](https://github.com/torvalds/linux/blob/master/include/trace/events/libata.h) | Upstream kernel source | 2026-07-24 | Current | Exposes `ata_qc_issue`, `ata_qc_complete_done`, and failed/internal completion events with ATA opcode and tag. |
| [Linux `libata-core.c`](https://github.com/torvalds/linux/blob/master/drivers/ata/libata-core.c) | Upstream kernel source | 2026-07-24 | Current | Calls `ata_qc_issue` immediately before the low-level driver's `qc_issue()` callback and completion tracepoints in `ata_qc_complete()`. |
| [libATA developer guide](https://docs.kernel.org/driver-api/libata.html) | Official kernel documentation | 2026-07-24 | Current | Describes SCSI-to-ATA translation, command issue, interrupt-driven completion, and flush translation. |
| [Kernel tracepoint API](https://docs.kernel.org/core-api/tracepoint.html) | Official kernel documentation | 2026-07-24 | Current | Defines the tracing mechanism used by the proposed discriminator. |

## Findings

### The no-MSI rule has not gone away

Current upstream still matches Samsung controller `144d:1600` to
`board_ahci_no_msi`. No later `ahci.c` change found in the current history
replaces that model with a safe MSI configuration. This agrees with the
physical result: MSI plus NCQ reads passed, but queued writes produced three
30-second timeout/reset waves. Writable MSI plus NCQ remains rejected.

### The starvation fix is relevant but not a complete explanation

Commit `0ea84089dbf6` solves a real scheduling failure: a non-NCQ command such
as an ATA flush can otherwise be repeatedly requeued while NCQ work from other
submission queues keeps arriving. Linux 7.1.3 contains that commit and its
subsequent deferred-command refinements.

The target's light raw test becoming fast on 7.1.3 is consistent with the fix,
but does not prove causation. The commit specifically discusses hosts with
multiple submission queues, while this one-port AHCI path has not yet been
shown to meet the starvation precondition during the captured workload.
Moreover, the heavier ext4 run still reached a roughly 1.1-second state.
Documentation should therefore say the commit *may explain part of the
improvement*, not that it solved this Mac's defect.

### The existing physical capture stopped one layer too high

The accepted legacy-stack artifact recorded block request issue/completion
events but no libata command events. The repository source now requests the
three relevant libata events, but that source postdates the physical artifact.
The old capture cannot be reinterpreted into ATA issue timing.

For a future run, pair these boundaries for opcode `ATA_CMD_FLUSH_EXT`:

1. `block:block_rq_issue` to `libata:ata_qc_issue`: time waiting below the
   block request boundary but before actual ATA submission;
2. `libata:ata_qc_issue` to `libata:ata_qc_complete_done`: time from the
   low-level AHCI issue path until libata observes completion;
3. `block:block_rq_issue` to `block:block_rq_complete`: end-to-end request
   service time.

The libata event contains the ATA opcode and tag, so this does not require
guessing which block flush became which hardware command.

### What command timing can and cannot decide

- If almost all of the 1.1 seconds occurs before `ata_qc_issue`, investigate
  libata/SCSI scheduling and the deferred-QC path.
- If almost all occurs between `ata_qc_issue` and
  `ata_qc_complete_done`, the delay is below libata scheduling.
- The second result still combines SSD execution, AHCI controller state,
  interrupt generation/delivery, and interrupt-handler observation. It does
  **not** by itself prove that the NAND/firmware spent the entire interval.
- Separating those lower layers would require a second, justified diagnostic
  that observes AHCI host/port state (`IS`, `PxIS`, `PxCI`, and `PxSACT`) near
  the delayed completion. That instrumentation should only be designed after
  command timing places the delay below issue.

## Product Implications

- There is no researched kernel parameter, distro change, or current upstream
  quirk that can honestly be called the SSD fix.
- The physical hardware remains capable of fast strict durability under
  Big Sur, so replacing the SSD is still not established as necessary.
- A rebuilt legacy-INTx capture with libata events is higher-value and safer
  than trying more NCQ/FUA/cache-policy combinations.
- No internal partition currently exists for that test. Research completion
  does not authorize rebuilding, repartitioning, provisioning USB media, or
  booting Linux.

## Host Rebuild Verification

On 2026-07-29, the legacy-INTx command-trace artifact was rebuilt twice from
clean output using the authenticated Linux `v7.1.3` source at commit
`199c9959d3a9b53f346c221757fc7ac507fbac50`. Both builds produced the same
manifest. The stable artifact hashes are:

```text
d2888d105727f622f34bb174e3cdf14e2aaa56a3e7e792bcea6bfdbe921a6f93  EFI/BOOT/BOOTX64.EFI
e2a4fdf0b1080d1a0582674cbab8c30cb0973cf4b9fb35a133087516cf1cd244  lab/vmlinuz
```

The rebuilt artifact passed its manifest, PE/EFI and kernel format checks,
required tracepoint and configuration checks, synthetic ext4 and dm-crypt
tests, copied-artifact readback, and `e2fsck`. This was host-only validation;
no USB was provisioned and no physical test was run.

## Recheck Triggers

- A new upstream change mentions `144d:1600`, Apple/Samsung SSD flush latency,
  AHCI MSI completion, or libata non-NCQ deferral.
- A future command trace places most delay before ATA issue.
- A future command trace places most delay after issue and justifies designing
  an AHCI-register capture.

## Open Questions

- Does the tested AHCI/SCSI queue topology actually exercise the multi-queue
  starvation condition fixed by `0ea84089dbf6`?
- In the slow state, is `PxCI` cleared promptly while legacy INTx completion is
  observed late, or does the command remain active in the controller?
- Why does macOS `F_FULLFSYNC` remain in the 6.9-13 ms range on the same
  controller and firmware?
