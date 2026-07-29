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
| Linux graphics | Upstream has Apple Set OS, `i915`, `apple-gmux`, and VGA switcheroo support | Linux is the chosen non-macOS graphics route, but full Big Sur parity remains unproven. |

## Existing Assets

### Authenticated storage baseline

- `scripts/prepare-kernel-source.sh` authenticates Linux `v7.1.3`, commit
  `199c9959d3a9b53f346c221757fc7ac507fbac50`, with Greg Kroah-Hartman's
  expected signing fingerprint.
- `scripts/build-filesystem-stack.sh` builds the stock `legacy-stack` trace
  artifact. Its rebuilt kernel hash is
  `e2a4fdf0b1080d1a0582674cbab8c30cb0973cf4b9fb35a133087516cf1cd244`.
- `scripts/initramfs/write-ab-init` enables block and libata issue/completion
  tracepoints, runs plain ext4 and dm-crypt plus ext4 workloads, verifies
  artifact/capture integrity, and reprotects every internal partition after
  the test.

The artifact deliberately refuses to run unless it finds an exact disposable
`MBPTEST` partition: partition 3 of the identified Apple SSD, in the final ten
percent of the disk, sized from 4 to 16 GiB, with all siblings read-only. The
former scratch partition was removed and full-size APFS was restored. Therefore
the artifact is valid and intentionally blocked, not stale or broken.

The 128 GB lab USB's last verified payload is the archived Windows
Intel-enumeration probe. Any Linux boot must deliberately replace it only after
the Linux artifact has passed its own rebuild, checksum, and writer checks.

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
measurement. Before any partition operation:

1. Capture and verify the current GPT/APFS/Windows layout and backups.
2. Obtain explicit user approval for one small final internal scratch partition.
3. Record its exact number, start sector, size, GPT name, and intended removal
   procedure.
4. Update the guard with those exact recorded values, review it, rerun synthetic
   safety tests, and reproduce the artifact before provisioning media.

This is the only planned internal-disk mutation. It is a temporary test volume,
not a Linux installation and never an APFS or Windows filesystem.

### 3. Establish Linux Intel-first graphics independently

Host-side work can proceed without touching the MacBook. The first physical
graphics boot must be a separate read-only EFI-stub/UKI appliance that:

- invokes upstream Apple Set OS through the kernel EFI stub;
- leaves `gpu-power-prefs`, GMUX registers, internal EFI, and the internal disk
  untouched;
- records whether both GPUs enumerate, `i915` binds, the panel has an Intel
  connector, and Apple GMUX/backlight initialize; and
- retains direct Big Sur and direct Windows recovery paths.

Only after that succeeds may a separate, user-present panel-routing design be
reviewed. It must write the firmware preference atomically and verify it from
an environment where Apple firmware permits readback. The rejected Windows
runtime writer is not reusable.

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
2. Rebuild and recheck the existing stock legacy-INTx trace artifact when
   needed; no hardware action is implied.
3. Design and host-validate the read-only EFI-stub/UKI Intel-enumeration
   appliance.
4. When explicitly approved, recreate a guarded scratch target and capture the
   physical flush trace.
5. Follow the trace result, not a predetermined driver theory.
