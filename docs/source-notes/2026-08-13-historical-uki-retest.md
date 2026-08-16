# Historical Intel UKI Retest (2026-08-13)

## Abstract

A controlled retest of the **only proven Intel-panel success image** (the
2026-08-01 UKI) failed to restore `i915drmfb`. macOS Big Sur wrote verified
Intel NVRAM (`gpu-policy=%01` and Intel `gpu-power-prefs`), followed by a
**cold shutdown**, then a manual Limine boot of a byte-identical copy of the
08-01 UKI. `i915` loaded, then disabled the internal eDP with
`failed to retrieve link info`. The primary framebuffer stayed `simpledrm`;
the NVIDIA driver loaded anyway. The machine remained reachable over SSH and
was restored to the known-good **NVIDIA LTS** desktop.

This closes the “just boot the old UKI with correct NVRAM” hypothesis. The
08-01 `i915drmfb` success remains the single unreproduced positive.

## Machine state at session start

Linux was already dual-boot with macOS. Windows was **not** installed. The
Limine default had been an experimental Intel UKI that can black-screen the
panel. That default was replaced before Intel work continued:

| Item | Value |
| --- | --- |
| Daily Linux | CachyOS `6.18.40-1-cachyos-lts` |
| Display GPU | NVIDIA GT 750M, driver `470.256.02` |
| Desktop | KDE Plasma X11 (`plasmashell` + `kwin_x11`) after restoring unmasked KDE user units |
| Panel | internal eDP 2880×1800 on the NVIDIA path |
| Idle NVIDIA | roughly 44–64°C, `P8`, fans ~2000 RPM — warm because it owns the panel, not thermally runaway |
| EFI `gpu-policy` on Linux | discrete (`%00`) until the macOS write below |

Plasma X11 needed extra work: SDDM session name must be `plasmax11.desktop`,
and previously masked KDE user units (`plasma-ksmserver` and related) had to
be unmasked. Hyprland/Wayland was left untouched (NVIDIA 470 is a poor fit).

## Historical UKI as a non-default Limine entry

The 08-01 success UKI was copied, not rebuilt:

- Source backup: `/boot/EFI/Linux/cachyos-apple-set-os.efi.bak-20260810-164347`
- Installed as: `/boot/EFI/Linux/cachyos-intel-historical-baseline.efi`
- SHA-256: `24e1fca10c8a7237b8e83fc74de22bc0be3d76bb17366d5329f78c823fcc0dea`
- Kernel inside the image: `7.1.5-1-cachyos` (same kernel series as the later
  `force_igd` UKI)
- **No** `apple_gmux.force_igd=1` and **no** later nvidia-off drop-in

Limine kept `RetinaForge NVIDIA LTS` as `default_entry: 1`. The historical
image was a **manual** menu entry only.

The current experimental `force_igd` UKI
(`/boot/EFI/Linux/cachyos-apple-set-os.efi`) was left in the menu and was
**not** the boot used for this retest.

## Firmware preparation (required for a valid test)

Linux cannot reliably write the Apple GPU NVRAM variables. From macOS
11.7.11, both values were set and read back **before** shutdown:

```text
gpu-policy=%01
gpu-power-prefs=%01%00%00%00
```

Then `shutdown -h now` (cold off, not restart). Power-on was physical. The
Limine choice was `RetinaForge Intel historical baseline`.

## Result (negative)

| Check | Result |
| --- | --- |
| UKI / 7.1.5 kernel | booted |
| NVIDIA blacklist in that UKI | present, but `nvidia` loaded later anyway |
| `i915` | loaded |
| Intel eDP | `failed to retrieve link info, disabling eDP` |
| Primary framebuffer | `simpledrmdrmfb`, not `i915drmfb` |
| Connected Intel eDP modes | none |
| SSH | stayed up |
| NVIDIA after boot | loaded, ~48°C, `P8` |

So: **correct macOS Intel NVRAM + the original success UKI is not enough** on
this date. Mux/firmware still presents the ghost-panel path to `i915`.

## Recovery

Limine default was set back to `RetinaForge NVIDIA LTS` and the machine was
rebooted. Confirmed after reboot:

- kernel `6.18.40-1-cachyos-lts`
- NVIDIA 470 driving the panel
- SSH reachable

Intel menu entries remain available for manual selection. They must not be
made default until `scripts/graphics/check-intel-first-panel.sh` passes.

## Display blanking (separate from GMUX)

On the NVIDIA Plasma session, KDE PowerDevil already reported `idleTime=0`,
but X11 DPMS was re-enabled later in the session. A keep-awake helper that
forced SDDM’s private `XAUTHORITY` failed silently (`xset` could not talk to
the user X server). Pointing the helper at the readable user auth file under
`/tmp/xauth_*` produced `DPMS is Disabled` and `Monitor is On`.

After that fix, the whole machine later dropped off the network (Tailscale
and LAN), which looks like **system sleep**, not panel DPMS. Sleep policy is
a separate control from GMUX experiments. In-tree helper:
`scripts/graphics/retinaforge-keep-display-awake.sh`.

## What this does not reopen

- Do **not** repeat “macOS `%01` + cold off + historical UKI” as the next
  experiment. It was run and failed.
- Do **not** re-enable the 2026-08-10 eDP-handoff profile as the default boot
  (it can wedge SSH). See
  [`2026-08-10-edp-handoff-research.md`](2026-08-10-edp-handoff-research.md).
- Do **not** live-switch GMUX mid-session.

## Ranked next Intel experiments (one variable each)

1. Stay on NVIDIA LTS as the default recovery desktop.
2. Investigate the remaining `force_igd` gap (eDP **connected**, **0 DRM
   modes**, Xorg `failed to set mode`) documented in
   [`2026-08-10-uki-intel-attempt-and-xorg-fail.md`](2026-08-10-uki-intel-attempt-and-xorg-fail.md).
   That path got further than this historical retest (link-info did not
   immediately disable eDP).
3. One-at-a-time `i915` cmdline sweeps (`enable_psr=0`, `fastboot=0`, PC8 /
   `enable_dc`) on the `force_igd` UKI only.
4. Initramfs/firmware diff of the 08-01 170 MB UKI vs the later ~151 MB
   `force_igd` image — already started; finish without changing the default
   boot.
5. Distro/kernel isolation (Debian/Mint/Fedora current) only with a user-present
   checkpoint; CachyOS is not assumed to be the blocker.

## Related notes

- Success: [`2026-08-01-intel-panel-and-display-path.md`](2026-08-01-intel-panel-and-display-path.md)
- Failed same-recipe retest: [`2026-08-05-intel-panel-path-retest.md`](2026-08-05-intel-panel-path-retest.md)
- Mux investigation closed: [`2026-08-08-limine-timeline-and-forced-dis-test.md`](2026-08-08-limine-timeline-and-forced-dis-test.md)
- `force_igd` breakthrough / 0 modes: [`2026-08-10-uki-intel-attempt-and-xorg-fail.md`](2026-08-10-uki-intel-attempt-and-xorg-fail.md)
