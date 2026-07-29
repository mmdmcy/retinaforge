# Native Read-Only Linux Baseline

Status on 2026-07-18: the source, build, bootloader, initramfs, capture path,
and destructive-writer guards passed host-side validation. The stock physical
MacBook capture and both opt-in MSI diagnostic stages have also completed. The
bounded read-only MSI-plus-NCQ stage passed at queue depth 32. The USB was
subsequently reprovisioned for writable diagnostics; its last recorded profile
is the rejected MSI-plus-NCQ stack, not this baseline or macOS recovery.

## Purpose

Boot a current upstream Linux kernel directly on the `MacBookPro11,3`, observe
the real `144d:1600` AHCI controller and `APPLE SSD SM1024F`, and collect a
sanitized Linux state snapshot without installing Linux or writing to the
internal APFS disk.

This is a baseline instrument, not a performance fix. It gives the project a
current, controlled Apple-versus-Linux comparison before any kernel source is
changed.

## Safety Contract

The appliance:

1. boots entirely from a FAT USB labelled `MBP_AHCI`;
2. identifies that labelled partition as the sole writable block device;
3. immediately applies and verifies the Linux block read-only flag on every
   other physical `sd*` or `nvme*` disk and partition;
4. requires the unambiguous 16-character SCSI model prefix
   `APPLE SSD SM1024` before capture;
5. never mounts APFS or another internal filesystem;
6. performs identification and state reads only, including PCI configuration,
   AHCI/libata sysfs state, ATA IDENTIFY, queue state, logs, and temperatures;
7. writes a sanitized, checksummed report only to the lab USB; and
8. syncs, unmounts the USB, and powers off.

The model prefix intentionally omits the final `F`: Linux exposes ATA devices
through a 16-character SCSI model field even though ATA IDENTIFY retains the
full `APPLE SSD SM1024F` identity.

The appliance does not install a bootloader internally, change EFI variables,
repartition storage, unlock encryption, start networking, run a write
benchmark, or modify macOS.

## Upstream Baseline And Provenance

- Linux stable tag: `v7.1.3`.
- Commit: `199c9959d3a9b53f346c221757fc7ac507fbac50`.
- Tag signer fingerprint:
  `647F28654894E3BD457199BE38DBBDC86092693E`.
- Kernel release string: `7.1.3-mbp-ahci-baseline`.
- Kernel source changes: none.

`scripts/prepare-kernel-source.sh` fetches the tag from kernel.org, obtains the
signer key through kernel.org WKD into an isolated ignored keyring, checks the
exact fingerprint and commit, and refuses a dirty or mismatched source tree.
See the [dated source note](source-notes/2026-07-17-upstream-baseline.md).

## Build

From the repository root on an x86-64 Linux build machine:

```bash
scripts/prepare-kernel-source.sh
scripts/build-readonly-baseline.sh
```

The kernel build requires `bison`, `flex`, and the libelf development headers.
The builder checks these prerequisites before creating its output tree.

The ignored artifact directory contains:

```text
build/readonly-baseline-v7.1.3/artifact/
├── EFI/BOOT/BOOTX64.EFI   # standalone GRUB EFI fallback
├── lab/vmlinuz            # Linux kernel with embedded initramfs
├── lab/grub.cfg            # review copy of embedded boot policy
├── lab/kernel.config       # exact normalized kernel configuration
└── SHA256SUMS
```

The build fixes the source commit, signer, build user/host/version/timestamp,
archive order, ownership, timestamps, boot policy, and command line. It rejects
a stale embedded init, a mismatched source tree, a missing required driver, or
an invalid x86-64 EFI binary.

## Provision A Dedicated USB

As a general rule, do not repurpose known-good macOS recovery media. In this
project the former recovery-bootstrap USB was later erased with explicit
permission, so it is no longer a recovery asset. The writer erases the entire
selected USB and never auto-selects a device.

First run read-only validation:

```bash
scripts/write-readonly-baseline-usb.sh --device /dev/sdX
```

The script prints a token containing that exact device and byte size. Review
the displayed model, existing signatures, and mount state. Only then use the
exact printed token:

```bash
sudo scripts/write-readonly-baseline-usb.sh \
  --device /dev/sdX \
  --confirm 'ERASE:/dev/sdX:EXACT_BYTE_SIZE'
```

The writer accepts only a whole removable USB disk from `/dev/sdb` through
`/dev/sdz`, between 4 and 256 GiB. It refuses `/dev/sda`, non-USB transport,
non-removable media, mounted children, active swap, and a root-backed device.
After writing, it verifies every artifact from the USB and runs a read-only FAT
filesystem check.

## First Physical Boot

1. Leave the working internal Big Sur installation unchanged and shut down the
   MacBook normally.
2. Insert only the dedicated lab USB.
3. Power on while holding Option/Alt and select the external `EFI Boot` entry.
4. Do not type commands or interrupt collection. A successful run reports its
   output path, waits ten seconds, and powers off automatically.
5. Remove the lab USB and boot Big Sur normally.

If the appliance opens an emergency shell, photograph the exact error and run
only `poweroff -f`. Its internal filesystems remain unmounted, but the failed
run should be diagnosed on the build machine before another boot.

## Retrieve And Compare

Reconnect the lab USB to the Linux workstation. Successful reports are under
`captures/<UTC timestamp>/` on the USB and contain a `COMPLETE` marker plus a
local `SHA256SUMS` file. Raw reports remain ignored and must be sanitized again
before any finding is committed.

The first comparison should cover only state that can distinguish the two
operating systems: controller capabilities and registers, interrupt mode, NCQ
and queue depth, cache/FUA exposure, link power state, AHCI port state, and
command-line quirks. One material difference is selected for the next
experiment; no patch should combine unrelated variables.

## Physical Results And Appliance Extension

The stock Linux `7.1.3` physical run met the safety contract and confirmed the
existing `144d:1600` no-MSI quirk selects legacy INTx on the target controller.
That result, compared with Big Sur's MSI-enabled state, selected interrupt mode
as the next single variable.

The appliance was extended with a diagnostic kernel whose boot-time opt-in is
scoped to DMI model `MacBookPro11,3` and PCI ID `144d:1600`. The first physical
stage combined MSI with forced non-NCQ. It reported one MSI vector and queue
depth 1, completed without an ATA error, reset, or timeout, preserved the
internal SSD read-only state, and powered off automatically.

An empty built-in SD-card reader initially appeared as a zero-capacity `sd*`
device during discovery. The guard now waits for topology to settle, skips only
devices whose sysfs size is exactly zero, and rechecks the target SSD's
read-only state before collection. The skip is narrow and does not relax the
internal-disk protection.

The next appliance variant removed only `libata.force=noncq` and ran four
bounded concurrent direct-read workers. It passed with MSI enabled, queue depth
32, all readers complete, 555 AHCI MSI interrupts, no ATA fault, valid report
and artifact checksums, and the same mandatory read-only target. These
read-only stages establish controller safety; they do not benchmark the
unresolved durable-write latency.

## Host-Side Verification Baseline

Before physical provisioning, the current appliance passed:

- exact tag, commit, and signer-fingerprint verification;
- two consecutive byte-identical artifact and initramfs builds;
- checks that no local home-directory path or builder UID entered the kernel;
- x86-64 PE and EFI-application checks for GRUB and the kernel EFI stub;
- OVMF boot through USB, standalone GRUB, Linux, capture, and poweroff;
- a synthetic `APPLE SSD SM1024F` target forced read-only before collection;
- report checksum, FAT filesystem, and unchanged target-backing-image checks;
- a negative test proving the writer refuses the build machine's `/dev/sda`.

QEMU/OVMF validates the boot and safety machinery only. It cannot validate the
Apple AHCI behavior because the real PCI controller and SSD firmware exist only
on the physical MacBook.
