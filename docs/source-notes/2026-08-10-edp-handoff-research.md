# Indexed GMUX eDP Handoff Research (2026-08-10 evening)

## Problem recap

On MacBookPro11,3 with indexed GMUX (`4.0.8 [indexed]`), the Intel UKI path with
`apple_gmux.force_igd=1` yields:

- `IGD:+` in vga_switcheroo
- i915 `card1-eDP-2`: **connected**, EDID readable, `link-status: Good`
- Kernel DRM **0 modes** on the eDP connector
- Xorg picks 2880×1800 from EDID then `failed to set mode: No such file or directory`
- Black panel, SSH OK

`modetest` shows encoder 92 present but **crtc 0**, connector 93 **modes 0**.

## Kernel mechanism (indexed retina)

From mainline `apple-gmux.c` and `vga_switcheroo` docs:

| GMUX type | Handler flag | Panel AUX |
| --- | --- | --- |
| pre-retina (PIO) | `CAN_SWITCH_DDC` | DDC/AUX can mux to inactive GPU for EDID |
| retina (indexed/T2) | `NEEDS_EDP_CONFIG` | **Cannot** mux AUX separately |

Retina panels set **NO_AUX_HANDSHAKE_LINK_TRAINING** in DPCD. The **active** GPU
must train the eDP link; when switching to the inactive GPU, link parameters are
passed through vga_switcheroo so the inactive driver can skip AUX handshake.

## Why `force_igd` may be wrong here

`force_igd` (CachyOS-patched `apple_gmux` module param) logs
`apple_gmux: Switching to IGD` at ~1.8s — **before** nouveau loads (~2.4s) and
**before** any GPU trains the panel.

Boot timeline (force_igd session):

```text
1.79s  apple_gmux: Switching to IGD
2.61s  nouveau DRM init (inactive client, no eDP modes)
3.84s  i915 DRM init — "Cannot find any crtc or sizes"
3.85s  vga_switcheroo: enabled
```

i915 becomes active on the mux without receiving pre-calibrated link state from
nouveau. EDID may still appear (ghost path / partial probe) but mode enumeration
never completes.

### Contrast: DIS-first with nouveau

With `force_igd` **disabled** and nouveau allowed, live `modprobe nouveau` on an
IGD-forced boot still showed 11 modes on `card0-eDP-1` when the mux was on DIS.
`echo IGD` mid-session set `IGD:+` but the panel stayed on nouveau — expected
when handoff happens without the proper boot-time client registration order.

## Hypothesis

**Boot-time sequence should be:**

1. `apple_set_os` UKI — Intel GPU enumerated
2. GMUX stays on **DIS** (firmware `%00` or no `force_igd`)
3. **nouveau** loads first, trains eDP, builds DRM modes on `card0-eDP-1`
4. `echo IGD` to vga_switcheroo — gmux switches panel (nouveau still has trained link)
5. **Then** `modprobe i915` — Intel probes as the active mux client
6. i915 should populate modes on `card*-eDP-*`
7. Optional `echo OFF` — power down DIS

This mirrors the MacBookPro 11,5 AMD guide (systemd oneshot switch at boot) but
accounts for indexed GMUX needing DIS link training first.

## In-tree experiment: `enable-intel-edp-handoff.sh`

| Component | Setting |
| --- | --- |
| `force_igd` | **removed** (no modprobe, no cmdline) |
| UKI mkinitcpio | `MODULES=(apple-gmux nouveau)`; **no `kms` hook**; no i915 |
| UKI cmdline | `modprobe.blacklist=i915` (lifted in handoff script) |
| `retinaforge-gmux-edp-handoff.service` | runs `gmux-edp-handoff.sh` before display-manager |
## Boot experiments (2026-08-10 evening)

### v1 — i915 before `echo IGD`

- nouveau: 10 modes on `card0-eDP-1` (DIS active)
- `modprobe i915` while DIS still `+` → `failed to retrieve link info, disabling eDP`
- `echo IGD` after failed i915 probe → switcheroo `IGD:+` but 0 Intel modes

### v2 — `echo IGD` before `modprobe i915`

- nouveau trains link successfully on DIS
- switcheroo reaches `IGD:+`, nouveau powered off
- i915 loads after switch but still `failed to retrieve link info`
- Panel stays on `nouveaudrmfb`; i915 has **no connectors** in modetest

**Conclusion so far:** indexed `NEEDS_EDP_CONFIG` requires **both** drivers
registered during the switch so link params can pass from nouveau → i915.
Loading only one side at switch time is insufficient.

### v3 — `i915 disable_display=1`, switch, reload i915

`gmux-edp-handoff.sh` now:

1. nouveau trains on DIS
2. `modprobe i915 disable_display=1` (switcheroo client, no eDP probe)
3. `echo IGD`
4. `modprobe -r i915 && modprobe i915` (probe as active client)

| `gmux-edp-handoff.sh` | nouveau wait → `i915 disable_display=1` → `echo IGD` → reload i915 → `echo OFF` |

Build:

```bash
sudo ./scripts/graphics/enable-intel-edp-handoff.sh
sudo INTEL_UKI_PROFILE=handoff ./scripts/graphics/build-apple-set-os-uki.sh
```

Revert to force_igd profile:

```bash
sudo ./scripts/graphics/enable-intel-daily.sh
sudo INTEL_UKI_PROFILE=force_igd ./scripts/graphics/build-apple-set-os-uki.sh
```

## Other ranked follow-ups (unchanged)

1. Diff Aug-1 vs current UKI initramfs (170 MB vs ~151 MB) for missing firmware
2. `i915.enable_psr=0`, `i915.fastboot=0` one-at-a-time on whichever profile works
3. Upstream: file/trace if handoff still yields 0 modes after correct DIS-first boot
4. macOS `%01` NVRAM — still useful for firmware policy but not sufficient alone

## Measurement template (post-reboot)

```bash
sudo journalctl -b -u retinaforge-gmux-edp-handoff.service --no-pager
sudo modetest -M i915 -c | awk '/eDP|mode/'
sudo modetest -M nouveau -c | awk '/eDP|mode/'  # before OFF
dmesg | grep -iE 'apple_gmux|switcheroo|i915.*edp|Cannot find'
```
