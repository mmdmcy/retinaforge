# Intel-first Linux panel reproduction — MacBookPro11,3

This is a **distro-agnostic** cook-book for getting the internal Retina panel
owned by Intel `i915` on `MacBookPro11,3` (Iris Pro `8086:0d26` + GT 750M
`10de:0fe9` + Apple GMUX). It records what this workbench verified on
2026-08-01 and how someone else can repeat the path.

Evidence write-up:
[`docs/source-notes/2026-08-01-intel-panel-and-display-path.md`](../source-notes/2026-08-01-intel-panel-and-display-path.md).

The lab distro happened to be CachyOS + Limine. **Debian, Fedora, Arch, etc.
are fine** if they can boot a kernel through the **EFI stub** (UKI or equivalent)
so upstream `apple_set_os()` runs, and the kernel is new enough to include
Apple product support for this model (see upstream commit `71e49eccdca6` and
later product-name fallback). Prefer a current Fedora or Debian *testing*/backports
kernel over a very old stable if Set OS / i915 on dual-GPU Macs misbehave.

## Why this is fiddly

Apple EFI firmware does not treat Linux like a generic PC. Without Apple Set OS,
the iGPU often never enumerates. Panel selection also depends on the Apple
`gpu-power-prefs` EFI variable, which this workbench could only write reliably
**from macOS**. Live GMUX forcing from Linux caused black screens and is not
part of the recipe.

## One-time prerequisites

1. Keep a bootable macOS install (recovery reference).
2. Install Linux on a separate partition (plain ext4 is enough for graphics lab
   work). Do not mix this procedure with writable MSI+NCQ storage experiments
   on the Apple AHCI `144d:1600` controller.
3. Install a bootloader entry that chainloads a **UKI** or other EFI application
   that enters the kernel via the **EFI stub**.  
   **Not sufficient:** Limine/GRUB `protocol: linux` / plain `linux`+`initrd`
   without EFI-stub entry — on this machine that path skipped Apple Set OS.
4. Kernel modules: `i915`, `apple-gmux`, Nouveau or other NVIDIA client optional
   for switcheroo.

### Example Limine fragment (placeholders only)

```text
/+Linux Intel probe
comment: UKI via EFI stub for apple_set_os
  //uki
  protocol: efi
  path: boot():/EFI/Linux/your-uki.efi
```

Set that entry as default once verified. Keep a nomodeset / stock entry as
fallback.

## Step A — macOS: prefer Intel

From Terminal on macOS:

```bash
chmod +x macos/scripts/set-gpu-power-prefs-intel.sh
./macos/scripts/set-gpu-power-prefs-intel.sh
```

Or manually:

```bash
sudo nvram fa4ce28d-b62f-4c99-9cc3-6815686e30f9:gpu-power-prefs=%01%00%00%00
sudo nvram fa4ce28d-b62f-4c99-9cc3-6815686e30f9:gpu-power-prefs
```

- Intel lab value: `%01%00%00%00`
- Discrete / macOS-oriented value: `%00%00%00%00`

On this workbench + Big Sur, also set **`gpu-policy`** (not only
`gpu-power-prefs`):

```bash
sudo nvram gpu-policy=%01
nvram -p | grep -i gpu
```

Or use `macos/scripts/prepare-intel-from-macos.sh`.

**Cold shutdown** (`sudo shutdown -h now`), not Restart, before the UKI boot.

## Step B — Boot Linux via EFI stub / UKI

Reboot holding the firmware boot picker if needed, select the Linux ESP, then
the **Intel probe / UKI** entry (not a bare `protocol: linux` fallback).

On this lab (2026-08-10): use the in-tree stack:

```bash
sudo scripts/graphics/enable-intel-daily.sh
sudo scripts/graphics/build-apple-set-os-uki.sh   # adds apple_gmux.force_igd=1
```

Limine autoboot: `scripts/graphics/limine-set-default-uki.sh` (flat UKI entry,
`default_entry: 1`, 5s timeout).

**Required on MacBookPro11,3 today:** UKI cmdline must include
`apple_gmux.force_igd=1`, and initramfs must load `apple-gmux` before `i915`
(see `scripts/graphics/mkinitcpio-intel-uki.conf`). Without this, i915 often
logs `failed to retrieve link info, disabling eDP` even when Set OS enumerates
the iGPU. With `force_igd`, eDP-1 may show **connected** while kernel DRM modes
are still empty — see
[`docs/source-notes/2026-08-10-uki-intel-attempt-and-xorg-fail.md`](../source-notes/2026-08-10-uki-intel-attempt-and-xorg-fail.md).

## Step C — Verify on Linux

```bash
chmod +x scripts/graphics/check-intel-first-panel.sh
sudo ./scripts/graphics/check-intel-first-panel.sh
```

Critical expectations:

| Check | Expected |
| --- | --- |
| PCI | `8086:0d26` present |
| fb0 | name contains `i915` |
| DRM | eDP connected (Retina often 2880×1800) |
| switcheroo | `IGD:+:Pwr` |
| optional | `DIS: … Off` for cooler idle |

### Optional: power down discrete client

Only after IGD owns the panel:

```bash
echo OFF | sudo tee /sys/kernel/debug/vgaswitcheroo/switch
sudo cat /sys/kernel/debug/vgaswitcheroo/switch
```

Re-check after later boots; `DIS` may return to `Pwr`.

**Do not** use live mid-session IGD/DIS handoff or `mbp-cool-idle`-style
switcheroo hacks as a substitute for Steps A–B. Boot-time `force_igd` on the
UKI path is documented above; it is not the same as live forcing after login.

## External displays (separate from this recipe)

- **USB DisplayLink** can drive external 1080p panels with the GT 750M left
  off; sustained use is CPU-heavy and hot. Treat as occasional presenting.
- **Native** Thunderbolt/DP-style outputs on this generation still imply the
  discrete GPU path and are a different experiment (Nouveau / legacy
  proprietary). Do not claim them from a successful Intel-panel boot alone.

## Desktop notes (operator comfort, not driver proof)

- Prefer a light X11 desktop if the session must stay usable while testing
  (Xfce behaved better than a heavy Plasma session in this lab).
- On multi-GPU X11, point the compositor at the Intel DRM node when both cards
  enumerate.
- Retina scaling needs real toolkit scale inheritance (for example Qt 1.5), not
  only a settings checkbox that never reaches the session.

## Recovery

- Firmware boot picker → macOS.
- If Linux graphics is wrong: nomodeset / non-UKI fallback entry, or reset
  `gpu-power-prefs` from macOS to discrete `%00%00%00%00` for Apple-oriented
  behavior.
- Never chase a black screen with repeated live mux experiments.
- If the internal panel goes black but the machine is otherwise up (SSH /
  display manager still running): raise GMUX backlight sysfs brightness and
  restart the display manager before any mux experiments. If still black,
  force a re-modest of the panel connector (`xrandr --output eDP-1 --off`
  then `--auto` on the DIS-side X display); a 2026-08-07 recovery of the
  hybrid black-panel mode needed backlight max + sddm restart + that
  re-modest to bring the screen back. A 2026-08-05 retest hit a hybrid
  failure (Intel-oriented prefs attempt while Nouveau still owned the fb)
  that recovered via backlight + DM restart; see
  [`docs/source-notes/2026-08-05-intel-panel-path-retest.md`](../source-notes/2026-08-05-intel-panel-path-retest.md)
  and [`docs/source-notes/2026-08-06-intel-panel-investigation-and-migration.md`](../source-notes/2026-08-06-intel-panel-investigation-and-migration.md).

## Negative retest (2026-08-05)

The 2026-08-01 success was **not** reproduced by repeating Steps A–B alone
(including cold power-off and an integrated-only `pmset` lock on macOS).
`check-intel-first-panel.sh` failed with `nouveaudrmfb` and `i915` eDP
link-info errors despite UKI Set OS enumerating the iGPU. Do not claim a
working Intel desktop from prefs readback or iGPU PCI presence alone.

## Negative retest of the original UKI (2026-08-13)

Booting a byte-identical copy of the 08-01 success UKI after verified macOS
Intel NVRAM and a cold shutdown still produced `failed to retrieve link
info` / no `i915drmfb`. Do not repeat that pair as the next experiment.
Daily Linux should keep the proprietary NVIDIA LTS entry as Limine default
until the check script passes. See
[`docs/source-notes/2026-08-13-historical-uki-retest.md`](../source-notes/2026-08-13-historical-uki-retest.md).

## Distro migration (CachyOS → Debian/Fedora/…)

Graphics success here is **not tied to CachyOS**. When reinstalling:

1. Preserve macOS.
2. Recreate an EFI-stub/UKI boot entry (systemd-boot + UKI, or Limine `protocol:
   efi`, etc.).
3. Repeat Steps A–C.
4. Keep storage experiments and graphics experiments in separate boots.

Fedora’s newer kernels are often closer to upstream Apple quirks; Debian stable
may need a newer kernel package for the same comfort. Validate with
`check-intel-first-panel.sh` rather than assuming the brand name matters.

## What this recipe does *not* claim

- macOS-equivalent automatic graphics switching — **why** is written in
  [`docs/graphics/why-not-macos-ags.md`](why-not-macos-ags.md); this is an
  indexed GMUX / eDP-handoff limit, not a missing toggle
- GMUX physical rail-off proof beyond switcheroo `Off`
- Nouveau modeset or CUDA bring-up
- Fixing Apple AHCI durable-write latency (`144d:1600`)
