# Native Linux Roadmap On The Original SSD

Status: active investigation. The original `APPLE SSD SM1024F` remains in the
MacBook; replacing it, weakening durability semantics, and installing Linux
internally before the storage mechanism is understood are out of scope.

## Goal

Build a native Linux installation that approaches Big Sur's behavior on the
original hardware: reliable durable storage, Intel-primary internal graphics,
safe discrete-GPU power management, normal suspend/resume, and a documented
recovery path. This is a systems project with separate storage and graphics
acceptance gates. Passing one does not imply the other passes.

## Current Evidence

| Area | Established fact | Current conclusion |
| --- | --- | --- |
| macOS reference | Big Sur strict `F_FULLFSYNC` completed in 6.9-13.1 ms on the original SSD | The hardware has a fast strict-persistence path. |
| Linux legacy-INTx | Authenticated Linux `v7.1.3` was stable but reproduced roughly 1.1-second flush tails during the heavier ext4 and dm-crypt workload | Stable is not fast enough for a daily Linux root volume. |
| Linux MSI plus NCQ | Bounded reads passed, but writable queue-depth-32 testing produced three timeout/reset waves | Preserve the upstream no-MSI rule for writable NCQ. |
| Windows graphics probe | Apple Set OS exposed Iris Pro and started the Intel driver, but NVIDIA retained the panel | The Intel GPU is firmware-accessible; this does not prove panel routing or rail-off. |
| Linux graphics | Upstream has Apple Set OS, `i915`, `apple-gmux`, and VGA switcheroo support. Repeatable Intel panel ownership (2026-08-16): `force_igd` plus a pre-i915 `DDI_A_4_LANES` poke yields `i915drmfb` 2880×1800. NVIDIA LTS remains SSH recovery only. | Linux is the chosen non-macOS graphics route. Keep the discrete Limine entry for recovery; do not copy Big Sur AGS. |

## Existing Assets

### Authenticated storage baseline

- `scripts/prepare-kernel-source.sh` authenticates Linux `v7.1.3`, commit
  `199c9959d3a9b53f346c221757fc7ac507fbac50`, with Greg Kroah-Hartman's
  expected signing fingerprint.
- `scripts/build-filesystem-stack.sh` builds the stock `legacy-stack` trace
  artifact. Two clean 2026-07-30 builds were byte-identical and produced kernel
  hash `68b0c19409eafc19c955da74f3cd06169ca6f73a750cf7b0157d86998805e71f`.
- `scripts/initramfs/write-ab-init` enables block and libata issue/completion
  tracepoints, runs plain ext4 and dm-crypt plus ext4 workloads, verifies
  artifact/capture integrity, and reprotects every internal partition after
  the test.

The current artifact embeds the exact target size, partition count, partition
number, start sector, and sector count of the approved historical `MBPTEST`
geometry. It requires a newly created partition to match all of them and to be
the final 4-16 GiB child of the identified Apple SSD, with all siblings
read-only. No scratch partition exists now, so the appliance will fail closed
if booted in the current layout.

The 128 GB lab USB now contains the verified appliance on its 1 GiB FAT lab
partition. The writer preserved its separate APFS data partition, performed
write-time and independent read-only artifact checks, and left the APFS block
device read-only on the Linux host. No physical Linux boot has occurred.

### Graphics baseline

The current storage appliance is not a graphics test: it uses `nomodeset` and
the GRUB `linux` command. A future graphics appliance must boot a kernel through
its EFI stub or a UKI, permit `i915`, and collect graphics state. It must remain
read-only with respect to the internal disk until storage has a tested path.

## Next Technical Gates

### 1. Locate the storage delay

The highest-value next physical test is the existing stock legacy-INTx trace,
not another MSI experiment. For each actual `ATA_CMD_FLUSH_EXT`, compare:

1. block request issue to `ata_qc_issue`;
2. `ata_qc_issue` to `ata_qc_complete_done`;
3. block request issue to block completion.

Interpretation is deliberately narrow:

- Mostly before ATA issue: investigate SCSI/libata scheduling or deferred-QC
  behavior; a small strict Linux fix may be possible.
- Mostly after ATA issue: inspect AHCI `PxCI`, `PxSACT`, `PxIS`, and host
  interrupt state around completion; the cause is lower than scheduler policy.
- AHCI state clears before Linux completes the request: investigate completion
  delivery/observation rather than SSD media latency.

No result justifies disabling barriers, suppressing `fsync()`, accepting a
write cache lie, or re-enabling MSI plus NCQ writes.

### 2. Recreate a disposable scratch target only with authorization

The trace needs a physical durable-write workload on the internal controller.
A loop image, VM, APFS mount, or external USB filesystem cannot supply that
measurement. The current USB already embeds the historical scratch contract, so
prefer recreating that exact geometry and skipping rebuild/reprovision.

Before any partition operation:

1. Capture and verify the current GPT/APFS layout read-only.
2. Obtain explicit user approval for one small final internal scratch partition.
3. Create final `MBPTEST` matching parent `1954210120` sectors, partition 3,
   start `1937909760`, length `16300032` sectors when possible.
4. Inventory the real start/size/name. Rebuild and reprovision only if those
   values cannot match the already embedded command line.

This is the only planned internal-disk mutation. It is a temporary test volume,
not a Linux installation and never an APFS volume. Big Sur remains the bootable
fallback on the APFS container.

### 3. Establish Linux Intel-first graphics independently

**Status 2026-08-01: panel ownership gate passed** on the internal dual-boot
CachyOS/Limine UKI path. Evidence:
[`docs/source-notes/2026-08-01-intel-panel-and-display-path.md`](source-notes/2026-08-01-intel-panel-and-display-path.md).

Remaining graphics gates (still open):

- measured discrete rail-off vs switcheroo `OFF` only;
- suspend/resume with Intel panel ownership;
- native GT 750M external outputs (separate from USB DisplayLink);
- no claim of macOS-equivalent automatic switching (see
  [`docs/graphics/why-not-macos-ags.md`](graphics/why-not-macos-ags.md)).

Host-side UKI/Apple Set OS design notes remain in the 2026-07-24 graphics
source note. Do not reopen live GMUX forcing after black-screen incidents.

### 4. Prove discrete-GPU power behavior

Intel panel ownership, a missing NVIDIA driver, PCI D3hot, and physical rail-off
are different states. A Linux daily-driver claim requires measured evidence for
the selected state, repeated suspend/resume, internal-panel stability,
backlight, audio, and external-display behavior. Do not claim Big Sur-equivalent
rail-off before the GMUX handler and GPU/HDA driver sequence prove it.

## Decision Rules

- A patchable strict-storage mechanism proceeds to a side-by-side test kernel.
- A lower-layer slow completion proceeds only to justified register capture; it
  is not treated as an SSD replacement mandate.
- Any reset, ATA timeout, filesystem warning, unverified firmware write, or
  graphics regression stops that branch and returns to Big Sur.
- A persistent internal Linux install is considered only after strict storage,
  Intel panel, and recovery gates pass independently.

## Near-Term Order

1. Keep Big Sur and Windows operational as recovery references.
2. Keep validating the stock legacy-INTx trace harness without creating a
   geometry-free boot artifact.
3. Design and host-validate the read-only EFI-stub/UKI Intel-enumeration
   appliance.
4. When explicitly approved, create and inventory a guarded scratch target,
   build two identical geometry-bound artifacts, provision the verified lab
   USB at a separate checkpoint, and capture the physical flush trace.
5. Follow the trace result, not a predetermined driver theory.
