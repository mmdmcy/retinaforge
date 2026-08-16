# Max value on this MacBookPro11,3 — 750M, Steam, Omarchy, macOS

This is the written-down recipe for the Late-2013 15-inch Retina that
RetinaForge actually tests (Iris Pro + GT 750M + indexed Apple GMUX).
It is not a 2026-GPU wish list. It is how to use **both chips you already
paid for** without blacking the lid.

The tray plate (`apps/mbp-panel/`) is the daily control. The **?** on that
plate is the short version of this file.

## What you have

| Chip | Job on the working Linux daily boot |
| --- | --- |
| Intel Iris Pro | Owns the internal panel (`i915drmfb`, 2880×1800). Desktop, browser, Proton/Vulkan. |
| GT 750M (2 GB) | Optional **render** helper. Wake it, then **Run on 750M**. Intel still owns the lid. |

macOS Automatic Graphics Switching is **not** this. On this muxed Retina,
Apple often **moves the panel cable** to NVIDIA. Linux must not send `IGD`
or `DIS` from a running desktop — that hop blacks the lid. The plate
refuses those writes.

Sleeping the 750M at idle is not wasting it. macOS parked it when idle
too. Powered-but-unused DIS is extra heat for the same picture.

## Daily (no reboot)

1. Boot the **Intel UKI** (Limine default on this workbench).
2. Jewel **sage** = 750M asleep. Leave it.
3. OpenGL app / native Linux Steam title: plate → type `glxgears` or
   `steam` (or **…** browse) → **Run on 750M**. That wakes the chip if
   needed and starts `DRI_PRIME=1` / `prime-run`.
4. When that app exits: **Sleep 750M**.

You do **not** need a reboot to use the 2 GB for OpenGL offload.

## Steam

| Kind of game | Chip | What to do |
| --- | --- | --- |
| Native Linux OpenGL | 750M | **Run on 750M** with `steam` (or the game binary) |
| Windows / Proton (most of the catalogue) | Iris Pro Vulkan on this boot | Start Steam normally. Lower in-game resolution; 2880×1800 is the tax |
| “I want NVIDIA Vulkan / 470” | 750M via proprietary driver | Reboot **NVIDIA LTS** Limine recovery. Different driver world; cannot share the chip with `nouveau` |

Do not expect 2026 settings. Do expect that dropping to 1920×1200 or
1440×900 is how this panel stays playable.

## NVIDIA 470 reboot (only this)

Use the numbered Limine **linux-cachyos-lts** recovery entry when you
need the last proprietary Kepler driver (CUDA, their Vulkan). Then boot
the Intel UKI again for daily use.

Do not bind 470 on the Intel-lid session. Do not look for a 470 toggle
on the plate.

## Omarchy (later, not a wipe)

Omarchy is a **port**, not “boot the ISO and replace CachyOS.”

Hard stops:

- **Do not** run the stock Omarchy ISO against this internal Apple SSD
  as a dedicated-drive install. That wipes the disk, including macOS.
- Omarchy’s getting-started text still describes a dedicated drive and
  default **LUKS**. Quattro documents a **Free space** dual-boot aimed
  at Windows. This machine is **APFS + Linux**, not BitLocker/NTFS.
  Do not let an installer “pick the Apple SSD” unless you have already
  created free space **from macOS Disk Utility** and you are choosing
  **only that free space**.
- Do not shrink APFS from Linux.
- On this SSD, lab probes showed **ext4-on-dm-crypt** ~1.1 s durable
  sync tails. The working graphics install is **unencrypted ext4**.
  Skip LUKS here (`Ctrl+C` on Omarchy’s disk-format confirm, or a
  manual Arch install). Skipping LUKS does **not** skip the graphics
  stack.
- Omarchy is Hyprland/Wayland. This lab proved **X11** on i915.
  Wayland is untested. Stock Arch kernels may **lack** CachyOS
  `apple_gmux.force_igd`. Without that (or an equivalent mux switch
  before i915) plus the DDI A 4-lane poke, you get a black lid or
  0 DRM modes.

Required on any reinstall (same as
[`intel-first-repro.md`](intel-first-repro.md)):

1. Keep macOS (see below).
2. EFI-stub / UKI so `apple_set_os()` runs.
3. `force_igd` (or equivalent) **before** i915.
4. DDI A 4-lane poke, then load i915.
5. Compositor/Xorg on `PCI:0:2:0`.
6. `check-intel-first-panel.sh` must pass.

Fun-only Omarchy belongs on a spare disk or VM until that list is
ported. Manual dual-boot into **pre-shrunk free space** is the only
internal-SSD path worth discussing.

## Keep macOS (including a small partition)

Prefer **keeping** a bootable Big Sur APFS, even if you never log into
it. “Preferably none” is the worse call **on this specific muxed
laptop**, not a generic dual-boot opinion.

A local macOS partition gives you:

- A lid that still works when Linux graphics experiments fail (Option /
  Startup Manager). SSH is not a substitute for a black internal panel.
- Apple’s Intel + NVIDIA drivers as a known-good reference.
- Disk Utility, NVRAM reset from a real macOS, bless, local Recovery.
- A place to **shrink APFS safely** if you ever add another Linux.

Internet Recovery (`Option-Command-R`) can reinstall macOS **without** a
local partition: it lives in firmware, not on the SSD. That is a real
fallback on Intel Macs of this vintage, **if** Apple’s CDN still serves
a compatible image and the machine has working firmware Wi-Fi. It is
slow, it is not guaranteed forever for a 2013 model, and it does not
help you **while** the panel is already wedged and you needed a local
boot **now**.

Firmware updates for this chassis already ended with the last Big Sur
point release. Keeping macOS is not “so Apple can keep patching EFI.”
It is **recovery and a second graphics stack**.

A small partition is enough: enough for Big Sur to boot (tens of GB,
not hundreds). You do not need it as a daily OS.

Wiping macOS is reversible only if Internet Recovery or a USB installer
still works. Do not find that out after a stock Omarchy ISO.

## Plate buttons (memorize nothing)

| Control | What it does |
| --- | --- |
| Sleep 750M | `vgaswitcheroo` `OFF` — unused GPU sleeps. Mux stays IGD. |
| Wake 750M | `ON` — 750M powered for offload. |
| Run on 750M | Wake if needed, then start the typed/browsed command with `DRI_PRIME=1`. |
| ? | This file, short form. |

No control sends `IGD` or `DIS`.
