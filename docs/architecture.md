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

## Candidate control points

1. AHCI NCQ behavior and host queue depth.
2. SATA link power management.
3. PCIe ASPM / link state management.
4. Block scheduler and request queue limits.
5. Controller-specific AHCI flags or a targeted kernel quirk.

The first four are reversible configuration experiments. The fifth belongs in a
minimal, reviewable kernel patch with a hardware match and an explanation of
the observed failure mode.
