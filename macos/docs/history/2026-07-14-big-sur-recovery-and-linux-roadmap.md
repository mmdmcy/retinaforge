# MacBook Pro 2013: Big Sur Recovery, Daily Driver, And Future Linux Work

Date: 2026-07-14
Status: historical record; later strict-sync and Linux tests supersede parts of
this document

## Executive Decision

The Late-2013 15-inch MacBook Pro is currently a successful macOS daily driver.
Big Sur `11.7.11` runs cool, fast, and responsively on the original 1 TB Apple
SSD. Do not wipe it again merely to try another Linux distribution. Preserve
this working reference, make a backup, and run the already-prepared macOS
`fsync()`/`F_FULLFSYNC` comparison before deciding whether strict Linux driver
development can resume.

Future Linux work remains a serious goal. The preferred sequence is:

1. prove a local mechanism on this exact machine;
2. implement and validate the smallest Linux change;
3. keep a stock recovery path throughout testing;
4. submit a technically honest patch upstream if the mechanism is real;
5. pursue storage, ACPI, and NVIDIA/GMUX contributions separately.

The engineering repository is [retinaforge](https://github.com/mmdmcy/retinaforge),
and its detailed continuation plan is the
[Linux driver and upstream roadmap](https://github.com/mmdmcy/retinaforge/blob/main/docs/linux-driver-upstream-roadmap.md).

## Exact Hardware In Scope

- Apple model family: `MacBookPro11,3`, 15-inch Retina Late 2013.
- Processor: 2.6 GHz quad-core Intel Core i7.
- Memory: 16 GB 1600 MHz DDR3L.
- Internal storage: 1 TB `APPLE SSD SM1024F`, firmware `UXM6JA1Q`.
- Storage controller: Apple/Samsung PCIe AHCI, PCI ID `144d:1600`.
- Integrated graphics: Intel Iris Pro, reported as 1536 MB by macOS.
- Discrete graphics: NVIDIA GK107M GeForce GT 750M Mac Edition, 2 GB,
  PCI ID `10de:0fe9`.
- Wi-Fi: Broadcom BCM4360, PCI ID `14e4:43a0`.
- Display: 15.4-inch Retina, 2880x1800.
- Recovery medium: corrected 128 GB OpenCore/recovery USB.

[Apple's technical specification](https://support.apple.com/en-la/111971)
confirms the configurable 2.6 GHz quad-core CPU, 16 GB memory, 1 TB storage,
Iris Pro, GT 750M, and Retina display combination.

## What Happened

### Linux Mint installation

- Linux Mint Cinnamon was installed with LUKS, LVM, and ext4.
- Broadcom Wi-Fi initially lacked its proprietary driver. An offline USB bundle
  installed `broadcom-sta-dkms` version `6.30.223.271`; Wi-Fi worked after a
  reboot.
- Git, Node through `nvm`, Codex CLI, and SSH were installed. Intermittent Wi-Fi
  caused at least one TLS download failure.
- The machine was extremely slow and felt hot. Broad repair attempts also
  produced a kernel panic, Xorg/Nouveau instability, and difficult GRUB/LUKS
  recovery. These incidents established the need for one-variable experiments
  and known-good boot entries.

### Storage investigation

- SMART and link evidence did not show a physically failed SSD.
- The machine exactly matched old Fedora and upstream reports for the
  Apple/Samsung `144d:1600` controller.
- Linux's existing no-MSI quirk was already active and fixed the older NCQ
  timeout class, but not the remaining durability latency.
- Ordinary writes could complete in milliseconds. The first following
  durability or non-write command then took roughly 0.8 seconds.
- NCQ, non-NCQ, FUA, both ATA flush opcodes, hardware write-through, power
  management changes, and temporary barrier suppression all failed.
- A model-scoped non-NCQ FUA patch was drafted but correctly rejected before
  installation because a runtime test exercised the same path and disproved
  its benefit.
- Reverse engineering Apple's signed AHCI drivers found no hidden vendor
  command or special controller setup that Linux could simply copy.

The strongest current explanation is that ordinary macOS synchronization
accepts weaker drive-cache persistence than normal Linux ext4 `fsync()`. Apple
provides `F_FULLFSYNC` for the stronger guarantee. The direct comparison on this
exact machine has not yet been run.

### Big Sur recovery

- Mint and the encrypted Linux layout were intentionally erased.
- Stock Internet Recovery started over Wi-Fi but later reached a recovery
  environment without a usable Wi-Fi control and could not install Big Sur.
- A 128 GB USB was prepared. It exposed `EFI Boot` and an OpenCore picker.
- The first OpenCore configuration halted because sample kext entries expected
  an absent `Lilu.kext` bundle. The configuration was corrected and validated.
- The corrected USB booted a compatible recovery environment with working
  Wi-Fi. Big Sur downloaded over the network and installed successfully.
- The USB was a recovery bootstrap, not a full offline installer. It can be
  removed for normal use but should be kept as an emergency recovery asset.

## Current macOS Role

This machine is practical for coding, terminal/SSH work, Git, documents,
browsing, ordinary multitasking, media, and light creative work. Its 16 GB RAM
and 1 TB internal storage remain substantial quality-of-life advantages.

The long-term limitation is software and security support. Big Sur is the final
official macOS branch for this model. Current development tools, browsers,
Xcode, Docker/virtualization software, and other applications may increasingly
require a newer macOS version. Test the actual work toolchain before depending
on the laptop for a deadline.

Back up the machine because the SSD and battery are old even though they are
currently behaving well. Keep at least one recovery route independent of the
internal disk.

## Steam And Gaming

Valve ended official Steam support for macOS 11 Big Sur on 2025-10-15. A client
that still opens or an older compatible Intel Mac game may remain usable, but
Steam on this OS is not a dependable long-term gaming platform.
[Valve's support notice](https://help.steampowered.com/en/faqs/view/659D-A19E-018A-81A6)
requires macOS 12 or newer for future client support.

Reasonable expectations:

- older Intel Mac games, indie games, and light 2D/3D titles;
- low settings and reduced resolutions such as 1280x800 or 1440x900;
- increased heat and battery use whenever the GT 750M is active.

Unreasonable expectations:

- modern AAA gaming;
- native 2880x1800 rendering in demanding 3D games;
- Apple-silicon-only builds or games requiring a newer macOS;
- long-term reliance on the current Steam client.

## Comparison With The Newer 256 GB MacBook

The exact model, chip, and RAM of the newer 256 GB MacBook are not recorded in
this folder, so a quantified performance comparison would be invented. The
stable comparison is:

- this 2013 MacBook wins internal capacity at 1 TB and provides ample local
  space for repositories, media, older games, and VM images;
- a genuinely newer Apple-silicon MacBook will normally win CPU/GPU speed,
  battery life, thermals, security support, and current application support;
- 256 GB is restrictive, but storage capacity is not equivalent to compute
  performance or software longevity.

Until the newer model is identified, use the 2013 machine as the spacious
legacy/workbench Mac and the newer machine as the safer current-software Mac.

## Future Linux And Kernel Contribution Plan

### Decisive next experiment

The prepared APFS strict-sync probe was later completed. Its procedure and
current interpretation are maintained in
[macos-fullfsync-test.md](https://github.com/mmdmcy/retinaforge/blob/main/docs/macos-fullfsync-test.md).

- Fast `fsync()`, slow `F_FULLFSYNC`: the current semantics explanation is
  confirmed. There is no proven fast strict operation to expose in Linux.
- Fast `fsync()` and fast `F_FULLFSYNC`: reopen driver work, capture the missing
  Apple state or command ordering, and develop a minimal AHCI/libata correction.
- Both slow: verify the test location and background load, then close the strict
  driver branch if repeated results agree.

### Storage contribution track

A strict upstream storage patch requires a demonstrated mechanism, a narrow
hardware match, side-by-side stock and patched kernels, repeatable before/after
traces, no ATA resets or filesystem warnings, and preserved durability. The
local fix must work before submission. The rejected non-NCQ FUA patch must not
be submitted as though it succeeded.

If strict persistence is inherently slow, a macOS-like Linux compatibility mode
would necessarily weaken normal `fsync()` guarantees. Such a mode must be
explicitly opt-in, prominently documented, and tested against the already
observed deferred-write stall. It may be useful locally without being suitable
for upstream Linux.

### Apple ACPI contribution track

Apple supplied a padded `_GTF` taskfile representation that Linux rejected.
The decoded ATA command did not improve performance and was rejected by this
SSD, so this is not the storage fix. A safe parser, diagnostic, or standards
compatibility improvement could still become a separate upstream contribution
if it is correct and tested on more than this one laptop.

### NVIDIA/Nouveau/GMUX contribution track

Writing a complete NVIDIA driver from scratch is not the sensible starting
point. Nouveau already supports the Kepler-family GT 750M. First reproduce one
specific defect—display updates, power management, suspend, GPU switching, or
Apple GMUX integration—without storage stalls contaminating the result. Then
fix that narrow behavior in the existing subsystem and submit it separately.

Never repeat the earlier live `vgaswitcheroo` plus display-manager restart
without a tested recovery path. Build kernels in a VM or another machine when
possible, and keep physical test boots bounded and reversible.

### Authorship and upstream process

The desired outcome is a real Linux kernel contribution under the human
author's identity. That requires understanding and reviewing the mechanism,
supervising or performing the hardware tests, maintaining the patch through
review, and signing the Developer Certificate of Origin truthfully. Use the
kernel's current `checkpatch.pl`, `get_maintainer.pl`, plain-text email workflow,
and submission rules at the time of submission.

AI can assist with research, code, test tooling, and revision, but it must not
create fake test claims or fake human authorship. Correctness and reviewable
evidence are what make the contribution resume-worthy.

## Immediate Checklist

1. Keep Big Sur and the recovery USB intact.
2. Create a current backup.
3. Run and save the sanitized macOS strict-sync probe results.
4. Test the real work applications needed over the next month.
5. Treat Steam as optional legacy compatibility, not a guaranteed platform.
6. Identify the newer 256 GB MacBook model before making a hard comparison.
7. Continue Linux work from the driver roadmap only after the strict-sync result.
