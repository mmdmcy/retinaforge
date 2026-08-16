# Haswell DDI A 4-lane poke restores i915drmfb (2026-08-16)

## Abstract

On `MacBookPro11,3`, `apple_gmux.force_igd=1` already switched the mux to IGD
and connected i915 eDP with a readable 2880×1800 EDID, but DRM advertised **0
modes** (`CLOCK_HIGH`). The panel DPCD is DisplayPort 1.1, HBR (2.7 Gbps),
**4 lanes**. i915 was using **2 lanes** because `DDI_BUF_CTL_A` lacked
`DDI_A_4_LANES` (bit 4). Setting that bit in MMIO, then (re)loading i915,
produces `i915drmfb`, kernel mode 2880×1800, and an Intel modesetting Plasma
X11 desktop. The path survived a UKI reboot with i915 delayed until after the
poke.

This is the first repeatable Intel-panel success since the unreproduced
2026-08-01 boot. It does **not** depend on macOS `%01` NVRAM or the historical
UKI image.

## Cause

Haswell `intel_ddi_max_lanes()` (`drivers/gpu/drm/i915/display/intel_ddi.c`)
reads `DDI_BUF_CTL(PORT_A)`. If bit `DDI_A_4_LANES` is clear, PORT_A is treated
as sharing 2 lanes with PORT_E. Two-lane HBR cannot carry 337.75 MHz at 24 bpp,
so `mode_valid` returns `CLOCK_HIGH` and the connector's mode list is empty.
Xorg then fails (`failed to set mode` / `no screens found`).

The kernel already documents this class of firmware bug:

> Some BIOS might fail to set this bit on port A if eDP wasn't lit up at boot.

Apple EFI on this machine always starts Linux UKI boots with the mux on DIS, so
Intel GOP never programs DDI A for 4 lanes. `intel_ddi_a_force_4_lanes()` only
overrides that for Broxton/Geminilake, not Haswell.

Live confirmation (force_igd UKI, after mux switch):

| Probe | Result |
| --- | --- |
| DPCD byte1 / byte2 | `0x0a` HBR, `0x84` 4 lanes + enhanced framing |
| `i915_dp_max_lane_count` | 2 (wrong) |
| `i915_display_info` | fixed mode 2880×1800 present, `modes:` empty |
| drm.debug | `Rejected mode: "2880x1800" ... (CLOCK_HIGH)` |
| `DDI_BUF_CTL_A` (MMIO 0x64000) | `0x00000081` (bit 4 clear) |

Writing bit 4 (`0x00000091`) and reloading i915:

| Probe | Result |
| --- | --- |
| `i915_dp_max_lane_count` | 4 |
| kernel modes | 2880×1800 |
| fb0 | `i915drmfb` |

`video=eDP-*:2880x1800@60e` was a negative: i915 logged
`User-defined mode not supported` for the same CLOCK_HIGH reason.

## Recipe that persisted across reboot

1. UKI / EFI-stub boot with `apple_gmux.force_igd=1` (mux to IGD).
2. Do **not** let i915 probe first. Initramfs loads `apple-gmux` + nouveau
   only; cmdline has `modprobe.blacklist=i915`.
3. Early systemd oneshot (before the display manager) writes `DDI_A_4_LANES`
   on `0000:00:02.0` BAR0, then `modprobe i915 enable_dc=0`.
4. Xorg `modesetting` on `PCI:0:2:0` with `AutoAddGPU false`, so the packaged
   NVIDIA OutputClass cannot steal the server.

In-tree installers: `scripts/graphics/enable-intel-daily.sh` and
`SKIP_LIMINE=1 scripts/graphics/build-apple-set-os-uki.sh`.

The oneshot is guarded with `ConditionKernelCommandLine=apple_gmux.force_igd=1`
so a Limine NVIDIA LTS recovery boot skips it.

## Verification (same boot that installed the UKI)

`scripts/graphics/check-intel-first-panel.sh` and
`scripts/graphics/verify-intel-uki-boot.sh` both returned critical pass:

- PCI `8086:0d26`
- fb0 `i915drmfb`
- i915 `eDP-2` connected, mode `2880x1800`, `i915_dp_max_lane_count=4`
- switcheroo `IGD:+:Pwr`
- Xorg modesetting + glamor on Iris Pro P5200, initial mode 2880×1800
- SDDM started Plasma X11

Warnings that are **not** blockers: discrete client still `Pwr`; Linux still
reads `gpu-policy` as discrete (`force_igd` already switched the mux).

## Durable kernel shape (not built this session)

A DMI quirk in `intel_ddi_a_force_4_lanes()` for `MacBookPro11,3` matches the
existing Broxton/Geminilake override. Lab sketch:
`patches/0003-i915-mbp11-3-ddi-a-4-lanes.patch`. Until a rebuilt kernel is
tested, keep the userspace MMIO poke.

## What this closes / leaves open

Closed: the `force_igd` connected-eDP / 0-modes gap from 2026-08-10.

Still out of scope: copying Big Sur Automatic Graphics Switching; making the
eDP-handoff profile the default boot; mixing storage (MSI+NCQ) into this path.

Optional later: switcheroo `OFF` for DIS after IGD owns the panel (breaks
`DRI_PRIME`); suspend/resume on this Intel desktop; replacing the poke with a
patched i915.

## Rebuild exactly (do not improvise)

From this repo, on kernel `7.1.5-1-cachyos` (not LTS):

```bash
sudo scripts/graphics/enable-intel-daily.sh
sudo SKIP_LIMINE=1 KVER=7.1.5-1-cachyos scripts/graphics/build-apple-set-os-uki.sh
```

UKI output: `/boot/EFI/Linux/cachyos-apple-set-os.efi`. Confirm embedded
tokens with a strings search (do not paste `root=UUID=…` into git):
`apple_gmux.force_igd=1`, `i915.enable_dc=0`, `modprobe.blacklist=i915`.

Limine: keep NVIDIA LTS as a recovery leaf; set `default_entry` to the Intel
UKI. Do not run `limine-set-default-uki.sh`.

Cook-book:
[`docs/graphics/intel-first-repro.md`](../graphics/intel-first-repro.md).

## Negatives from the same session (so they are not retried)

| Attempt | Outcome |
| --- | --- |
| debugfs `i915_dp_force_lane_count=4` | `max_lane_count` stayed 2; modes empty |
| `video=eDP-1:2880x1800@60e` (and eDP-2) | kernel: user-defined mode not supported |
| Live Xorg before the poke / without `40-intel-panel.conf` | NVIDIA OutputClass → no screens even after lanes were fixed until SDDM restart + Intel Xorg |

## Dual-GPU note recorded the same day

OpenGL `DRI_PRIME=1` → nouveau NVE7 while Intel owns the lid. Not AGS.
[`2026-08-16-dri-prime-nouveau.md`](2026-08-16-dri-prime-nouveau.md).
