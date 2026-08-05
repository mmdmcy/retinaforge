# MacBookPro11,3 Intel Panel Path Retest (2026-08-05)

## Abstract

A same-machine retest of the 2026-08-01 Intel-first internal-panel recipe
failed to restore `i915` ownership of the Retina eDP. EFI-stub / UKI boots
still exercised Apple Set OS semantics (Iris Pro enumerated; ACPI Darwin
`_OSI` path present), but `i915` reported failure to retrieve eDP link info
and disabled the connector. Nouveau remained the primary framebuffer owner
(`nouveaudrmfb`) with VGA switcheroo selecting the discrete client. macOS
`gpu-power-prefs` writes to the documented Intel value were verified by
immediate readback, yet returning to macOS later often showed the discrete
value again. The resulting hybrid (firmware preference aimed at Intel while
Linux drove the panel through Nouveau) produced a modeset flash / black
internal panel that recovered without live GMUX forcing. This note records
the negative result and operator recovery so the 2026-08-01 success is not
over-generalized as “always reproducible by raw NVRAM + UKI alone.”

## Context

| Item | Value |
| --- | --- |
| Model | `MacBookPro11,3` |
| Prior success | 2026-08-01 Intel panel path (`i915drmfb`, eDP 2880×1800) |
| Recipe under test | macOS Intel `gpu-power-prefs` + Limine UKI / EFI stub |
| Linux lab | CachyOS, current `linux-cachyos` UKI entry labeled for Apple Set OS |
| Reference OS | macOS Big Sur (APFS preserved) |

Related:

- [`2026-08-01-intel-panel-and-display-path.md`](2026-08-01-intel-panel-and-display-path.md)
- [`docs/graphics/intel-first-repro.md`](../graphics/intel-first-repro.md)
- Community mechanism notes still apply (`apple_set_os`, `gpu-power-prefs`,
  tools such as historical `gfxCardStatus` / `gpu-switch`); this session did
  not complete a verified Integrated-Only GUI tool lock beyond `pmset`
  `gpuswitch=0` plus NVRAM.

## Methods (aggregate)

Attempts were limited to the documented cook-book and close variants:

1. From macOS: delete/rewrite
   `fa4ce28d-b62f-4c99-9cc3-6815686e30f9:gpu-power-prefs` to
   `%01%00%00%00`, confirm readback.
2. Full power-off (not only soft reboot), then Limine **UKI / EFI-stub**
   Intel-probe entry (not bare `protocol: linux`).
3. On Linux: framebuffer name, DRM eDP status, switcheroo dump, package and
   GPU temperature samples, `dmesg` for `i915` eDP / Apple / Nouveau lines,
   and `scripts/graphics/check-intel-first-panel.sh`.
4. Additional macOS lock attempt: `pmset` graphics switch forced to
   integrated-only, then repeat prefs write, power-off, and UKI boot.
5. Linux-side `efivarfs` write patterned after community `gpu-switch` (attribute
   header + four data bytes) was attempted once; the variable remained
   unreadable / stub-sized (`EINVAL` on readback), consistent with prior
   “Linux is not a reliable writer” lab policy.

No live `apple_gmux.force_igd`, no writable MSI+NCQ storage work, and no APFS
resize or wipe were performed.

## Results

### 1. Apple Set OS path still wakes the iGPU

UKI boots showed Intel `8086:0d26` present with `i915` loaded and ACPI messaging
consistent with Darwin `_OSI` setup on Apple hardware. Stock
`protocol: linux` was not required to explain iGPU enumeration in these
boots—the stub path was in use.

**Finding.** Failure was not “iGPU missing.” The regression was panel / mux
ownership, not Set OS alone.

### 2. `i915` still could not claim eDP

Repeated UKI boots after verified macOS Intel prefs produced:

- `i915` encoder eDP link-info failure, connector disabled;
- primary fb name `nouveaudrmfb`;
- switcheroo discrete client selected and powered (`DIS:+:Pwr`) while IGD
  remained powered but not panel-owner;
- intel-first check script: critical failure.

**Finding.** On this date, macOS-verified `%01%00%00%00` plus UKI was
**insufficient** to reproduce the 2026-08-01 `i915drmfb` desktop.

### 3. Prefs did not stay Intel across OS round-trips

When macOS was entered again after Linux sessions, `gpu-power-prefs` often
read back as the discrete value `%00%00%00%00` until rewritten. Immediate
post-write readback on macOS showed `%01%00%00%00`. Linux `efivarfs` continued
to expose a stub / unreadable `gpu-power-prefs` object.

**Finding.** Treat persistence and firmware consumption of the preference as
an open variable. Do not assume a successful macOS write remains the effective
boot-time mux policy through later dual-boot cycles without re-checking on
macOS.

### 4. Hybrid preference / driver ownership → black panel, recoverable

With Intel-oriented preference attempts combined with Nouveau still owning the
framebuffer, the internal panel showed a brief full-screen artifact (white /
scan-line flash class) then went black. The Linux graphical session could
still be running (display manager + light X11 desktop present over the
network).

Recovery that restored a usable internal panel **without** GMUX register
experiments:

- raise the Apple GMUX backlight sysfs brightness to maximum;
- restart the display manager;

after which Nouveau again drove a visible desktop (thermally the discrete
path: package temperatures in the mid/high 60 °C class at light idle in these
samples—not the cooler Intel-owned idle class recorded on 2026-08-01).

**Finding.** Black screen here was not automatically “machine dead.” Prefer
remote or alternate-boot recovery over live mux surgery. Documented hard stop
on casual `force_igd` / live handoff remains.

### 5. Integrated-only `pmset` did not close the gap

Forcing macOS `gpuswitch` to integrated-only, confirming Intel as the active
macOS panel owner in `system_profiler`, rewriting Intel `gpu-power-prefs`,
powering off, and booting the UKI still yielded Nouveau primary fb and the
same `i915` eDP link failure.

**Finding.** Session-level macOS integrated graphics ≠ proven next-boot Linux
Intel panel ownership on this retest.

## Non-goals / not claimed

- No claim that the 2026-08-01 success was mistaken; this is a failed
  reproduction under current lab conditions.
- No root-cause isolation between firmware, SMC, NVRAM consumers, UKI contents,
  kernel `7.1.x` behavior, or missing GUI “Integrated Only” tools.
- No endorsement of Linux `efivarfs` writes for production use on this
  variable.
- No storage or MSI+NCQ results.

## Implications

1. Keep the 2026-08-01 recipe as the **best documented success**, but gate
   “it works on this laptop today” on a fresh `check-intel-first-panel.sh`
   pass—not on prefs readback alone.
2. Next graphics attempts should change **one** factor (for example a known
   Integrated-Only userspace tool on macOS, UKI/kernel skew vs 2026-08-01, or
   cold-boot timing) rather than repeating identical NVRAM + UKI loops.
3. Operator playbook when the hybrid black panel appears: backlight + display
   manager restart; firmware boot picker → macOS; optional discrete
   `gpu-power-prefs` `%00%00%00%00` for a predictable Nouveau desktop; never
   live GMUX force as first response.
4. Dual-boot daily use may remain on the discrete/Nouveau path until Intel
   panel ownership is re-proven.

## Reproducibility checklist (for a future positive pass)

- [ ] macOS readback of Intel `gpu-power-prefs` immediately before power-off
- [ ] Confirm Limine entry is EFI/UKI stub
- [ ] Record fb name, eDP status, switcheroo, package temp
- [ ] If black panel with SSH/network alive: try backlight + DM restart before
      mux experiments
- [ ] Re-check prefs on next macOS boot (persistence)
- [ ] Preserve APFS; no MSI+NCQ writable trials
