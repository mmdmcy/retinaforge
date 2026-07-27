# Architecture

## Storage path

```text
desktop / package manager
        |
     ext4 / journal
        |
      dm-crypt (optional)
        |
   Linux block scheduler
        |
   libata + ahci driver
        |
 Apple/Samsung PCIe AHCI controller
        |
       SSD firmware
```

The workbench focuses below the filesystem layer because observed stalls place
writers in uninterruptible I/O wait while CPU usage remains low. That makes a
desktop environment, filesystem theme, or CPU governor an unlikely primary
cause.

## macOS comparison

macOS uses Apple's storage stack. Linux distributions use the upstream Linux
`ahci` path unless a vendor-specific quirk is added. This is why Mint, Debian,
Fedora, and Arch should be compared using the same controller tests rather than
assumed to differ by default.

Inspection of Apple's signed Intel AHCI binaries narrowed this further. The
exact `144d:1600` Apple controller branch only publishes registry metadata.
Apple's strict synchronization path uses standard flush/FUA operations that
are also slow in the tested Linux state. Ordinary macOS `fsync()` has a weaker
documented drive-cache guarantee than Linux ext4 `fsync()`, but the measured
millisecond-scale macOS `F_FULLFSYNC` result proves that semantics alone do not
explain the cross-OS difference. Static driver inspection found no private fast
command, so the current boundary is runtime controller, device, power, cache,
or command-order state.

## Tested control points

1. AHCI NCQ, non-NCQ, FUA, and host queue depth: no usable strict path.
2. ATA `E7h` and `EAh` flushes: both slow.
3. Hardware write-through: slower.
4. SATA link power management and PCIe ASPM: not causal.
5. Legacy IRQ delivery: error-free but compatible with a sustained roughly
   1.1-second flush tail on current Linux. Forced MSI handles bounded reads but
   causes 30-second NCQ-write timeouts and link resets under `mkfs.ext4`.
6. Ext4 barrier suppression: unsafe and still incurs the deferred device wait.
7. Apple controller initialization: no missing vendor command found.

The remaining architecture boundary is durability and command completion.
Forced MSI plus NCQ is not a usable route, while the stock legacy path remains
correct but develops a slow-flush tail. The next trace must distinguish queue
time before the ATA flush is issued from device execution after issue. A
practical implementation must correct that proven layer, use a validated
MSI-plus-non-NCQ compatibility path if one is ever proven, weaken
acknowledgment semantics explicitly, or move persistence to a different
storage path. That MSI-plus-non-NCQ writable validation remains unrun.

## Candidate intervention layers

This project does not need a replacement for the complete AHCI driver. Linux
already discovers the controller, transfers ordinary data quickly, handles its
interrupt quirk, and reports clean device health. The candidate layers are:

```text
application and filesystem
        |
 [optional compatibility or shaping layer]
        |
 Linux block scheduler
        |
 [narrow libata/AHCI quirk, only if missing hardware behavior is proven]
        |
 existing libata + ahci driver
        |
 controller and SSD firmware
```

There are three materially different products that could emerge:

1. A strict AHCI/libata correction, if macOS proves the hardware can perform a
   real persistence operation quickly after different initialization or
   command ordering. This would be a small patch to the existing kernel path,
   not a new driver.
2. A strict responsiveness layer that preserves every flush but shapes ordinary
   I/O so an expensive persistence point freezes less unrelated work. This can
   improve usability but cannot make an individual 800 ms flush fast.
3. An explicitly opt-in compatibility layer that coalesces or defers some
   persistence requests. This could resemble ordinary macOS behavior, but it
   must expose its crash-loss window and must never masquerade as strict Linux
   `fsync()` durability.

An out-of-tree device-mapper target is the safest likely prototype for options
2 and 3 because it can intercept block requests on a test volume without
replacing AHCI or permanently forking Linux. If the mechanism proves generally
useful, it can later be redesigned for the appropriate upstream block layer.
The existing `barrier=0` negative result means such a prototype is not presumed
to work: request-pattern experiments must justify it first.
