# Why Linux cannot copy Big Sur Automatic Graphics Switching

This is the durable answer for later sessions. The product goal in this
repository is still **Intel `i915` owning the internal Retina panel**. That is
not the same as replicating macOS Automatic Graphics Switching (AGS).

Last updated: 2026-08-16.

## Short answer

Big Sur can keep both GPUs in play and move work (and sometimes the panel)
between Iris Pro and the GT 750M because Apple owns the firmware, both
drivers, the GMUX, and WindowServer as one product.

Linux on this `MacBookPro11,3` is a **muxed dual-GPU laptop**, not an Optimus
laptop. The internal eDP cable is wired to **one** GPU at a time through an
**indexed** Apple GMUX. The two Linux driver stacks that can drive those GPUs
do not implement Apple’s switching protocol, and this lab has not completed a
working eDP handoff even at boot. So we cannot honestly promise “it switches
like macOS.”

That is a hardware-plus-driver limit, not a missing config file.

## What macOS is actually doing

On this machine Big Sur does several things that look like one feature:

1. **Firmware mux pick at power-on** from `gpu-policy` / `gpu-power-prefs`.
2. **Runtime panel mux** through Apple GMUX when Automatic Graphics Switching
   wants the other chip to own the internal display.
3. **Per-app render offload** (heavy apps on NVIDIA, desktop on Intel) inside
   WindowServer.
4. **Coordinated power** of the GT 750M rails when it is idle.

Linux has pieces of (1) and (4) in `apple-gmux` + `vga_switcheroo`. It does
not have Apple’s (2)+(3) userspace, and this Retina GMUX makes (2) much
harder than on older non-Retina Macs.

## This is not an Optimus PC

Typical Linux hybrid laptops (Optimus):

- Intel **always** owns the internal panel.
- NVIDIA renders into a buffer; Intel composites it (`DRI_PRIME`).
- The panel cable never moves.

This MacBook Pro:

- A GMUX **physically selects** which GPU’s output is connected to the
  internal eDP.
- Native Thunderbolt/DP-style outputs on this generation stay on the
  **discrete** GPU even when the panel is on Intel (upstream GMUX docs).
- You cannot get “Intel drives the lid, NVIDIA drives HDMI” for free the way
  some PCs do. DisplayLink is a separate USB path, already tested.

So “use both GPUs like macOS” is not a PRIME checkbox. It is panel-mux
handoff plus power policy plus (maybe later) render offload.

## Why the Retina GMUX blocks a macOS-like switch

Upstream `apple-gmux` / `vga_switcheroo` distinguish two families:

| GMUX | Flag | Panel AUX / DDC |
| --- | --- | --- |
| pre-Retina (PIO) | `CAN_SWITCH_DDC` | can point DDC at the inactive GPU |
| Retina indexed (this machine, `4.0.8 [indexed]`) | `NEEDS_EDP_CONFIG` | **cannot** mux AUX separately |

This panel also advertises **no AUX handshake link training**. The **active**
GPU must train the eDP link. When the mux flips, the old driver is supposed
to hand those link parameters to the new driver through vga_switcheroo so
the new driver can skip AUX.

If that handoff does not happen, the new GPU may still see a connector and
even EDID, but it will not have modes, or it will log
`failed to retrieve link info, disabling eDP`. That is exactly the lab
record.

Lab evidence:

- Live `echo IGD` set `IGD:+` while the **panel stayed on nouveau**.
- DIS-first boot handoff (nouveau trains, then switch, then i915) reached
  `IGD:+` and still got i915 link-info failure.
  [`2026-08-10-edp-handoff-research.md`](../source-notes/2026-08-10-edp-handoff-research.md)
- `force_igd` switches the mux **before** either GPU has trained the panel:
  eDP becomes **connected** with Apple EDID, kernel DRM modes stay **0**,
  Xorg `failed to set mode`.
  [`2026-08-10-uki-intel-attempt-and-xorg-fail.md`](../source-notes/2026-08-10-uki-intel-attempt-and-xorg-fail.md)

Until that eDP config transfer works, runtime switching is how you get a
black lid, which is why live GMUX forcing is a hard stop.

## Firmware will not treat Linux like macOS

Controlled boots (2026-08-05 through 2026-08-08) showed: **every Linux UKI
power-on landed on `DIS:+`**, whether the previous macOS session ended on
Intel or NVIDIA, and whether `gpu-policy` was `%01`. The same NVRAM makes
macOS honor Intel on a macOS power-on.

The firmware is discriminating by **boot target**, not merely storing a mux
bit for Linux to inherit. `force_igd` is a CachyOS `apple_gmux` bypass of
that pick. It is not Apple AGS.

Details:
[`2026-08-08-limine-timeline-and-forced-dis-test.md`](../source-notes/2026-08-08-limine-timeline-and-forced-dis-test.md).

The 2026-08-13 retest then showed that even the **original 08-01 UKI** plus
verified macOS Intel NVRAM plus a cold off still ghosted the Intel eDP.
[`2026-08-13-historical-uki-retest.md`](../source-notes/2026-08-13-historical-uki-retest.md).

## The Linux drivers are not Apple’s pair

| Stack | Panel mux client | Notes on this lab |
| --- | --- | --- |
| macOS Intel + NVIDIA | yes, Apple protocol | AGS works |
| Linux `i915` + `nouveau` | both can register with vga_switcheroo | handoff still failed here |
| Linux `i915` + proprietary **nvidia 470** | **nvidia 470 does not register** | this is the **stable desktop**; it cannot join a switcheroo handoff |

The daily recovery OS is LTS + NVIDIA 470 because it actually lights
2880×1800. That driver is the one that **cannot** participate in
vga_switcheroo. Nouveau can participate, but it is not the stable desktop
and did not complete eDP handoff to i915.

There is also no Linux WindowServer equivalent that decides per-app “this
frame goes to NVIDIA, then mux the lid.” `DRI_PRIME` is buffer offload onto
whatever GPU already owns the display. It does not flip GMUX.

## What would have to be true before AGS is even discussable

All of these, in order:

1. `scripts/graphics/check-intel-first-panel.sh` passes: `i915drmfb`, eDP
   2880×1800, real DRM modes. **Currently false** except the unreproduced
   2026-08-01 boot.
2. A documented, non-wedging way to leave **both** `i915` and a switcheroo
   NVIDIA client registered (nouveau, not 470) without blacking the panel.
3. A successful **eDP link-parameter handoff** on this indexed GMUX (the
   08-10 v1–v3 experiments did not).
4. Only then: a userspace policy (switcheroo / custom daemon). That is still
   not Big Sur AGS; it would be a crude boot-or-manual mux.

Item 1 is the current Intel track. Items 2–4 are **not** the next
experiment. Do not combine them with (1).

## Realistic Linux shapes on this hardware

| Shape | Status | Like Big Sur? |
| --- | --- | --- |
| NVIDIA 470 owns the panel (current default) | works; warmer | no |
| Intel owns the panel; NVIDIA `OFF` after | **goal**; panel ownership still open | no; Intel-only |
| Boot-time mux pick (UKI / `force_igd`) | partial (`connected`, 0 modes) | no |
| Runtime AGS-style panel hop | failed in lab; hard stop | no |
| `DRI_PRIME` offload | only after Intel owns the panel | no; Optimus-like, not mux |
| Native TB/DP on GT 750M | separate experiment | no |

## What to do next (unchanged)

Keep Limine default on NVIDIA LTS. Next Intel work is filling DRM modes on
the `force_igd` connected eDP, one kernel/cmdline variable at a time. See
[`docs/session-handoff.md`](../session-handoff.md).

Do not start an “AGS on Linux” project until the Intel panel check script
passes on a repeatable boot.
