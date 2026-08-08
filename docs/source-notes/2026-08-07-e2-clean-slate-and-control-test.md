# E2 Clean-Slate Attempt and Control Test (2026-08-07)

## Abstract

First full E2 run (SMC reset → macOS Intel prefs → plain macOS reboot with
survival check → macOS-on-iGPU session → cold power-off → UKI boot) was
**negative**: the mux came up `DIS:+` on the Linux UKI boot despite a
byte-verified Intel state immediately before power-off. The designed control
test (cold power-off → boot macOS again) came back **Intel** with the
`gpu-policy` variable intact, so Linux did not destroy the variable and the
firmware can still honor the Intel policy — for macOS power-ons. Two
conclusions follow: hypothesis (c) (Linux destroys the variable) is refuted,
and the mux outcome is now observed to differ by **boot target** with
identical NVRAM state.

## New observations

### 1. There is a second variable: `gpu-policy` (no GUID)

After the SMC reset, `nvram -p` on macOS Big Sur shows:

```
gpu-policy   %01
```

with the panel on the iGPU. `gpu-power-prefs` (GUID `fa4ce28d-…`) is **not
listed** by `nvram -p` on this machine; it is only visible via a direct
GUID-qualified read (`sudo nvram "fa4ce28d-…:gpu-power-prefs"`). The two
variables behaved differently across the session:

| Variable | After SMC reset | After plain macOS reboot | After Linux UKI session (control test) |
| --- | --- | --- | --- |
| `gpu-policy` | `%01` | `%01` | `%01` |
| `gpu-power-prefs` | `%00%00%00%00` | `%00%00%00%00` (rewritten by macOS after our write) | `%00%00%00%00` |

`gpu-power-prefs` did not survive a macOS reboot — macOS rewrote it back to
discrete while the panel stayed on Intel via `gpu-policy %01`. On this
machine + Big Sur the firmware-visible lever appears to be **`gpu-policy`**,
not the `gpu-power-prefs` that the earlier lab docs (and the kernel apple-gmux
doc) assumed. The 08-01 success note never recorded which variable was
present; the 08-05 retest only wrote `gpu-power-prefs`.

### 2. Control test: macOS returns on Intel, variables survive Linux

Sequence run (E2 steps 0–6 exactly, plus the control):

1. One deliberate SMC reset (user-present), then macOS boot: panel on iGPU in
   `system_profiler`; `gpu-policy %01` present.
2. Wrote `gpu-power-prefs` `%01%00%00%00`; readback OK.
3. Plain macOS reboot: `gpu-power-prefs` flipped to `%00%00%00%00` (macOS
   rewrote it), `gpu-policy` stayed `%01`, panel still on iGPU in macOS.
4. Re-wrote `gpu-power-prefs` `%01%00%00%00` (byte-identical cold-off state),
   re-verified, panel confirmed on iGPU in macOS immediately before power-off.
5. Cold power-off → Limine UKI/EFI-stub boot (default entry, same UKI as
   08-01): **mux `2:DIS:+:Pwr`**, `nouveaudrmfb` primary, i915
   `failed to retrieve link info, disabling eDP` (ghost-panel path). Same
   kernel `7.1.5-1-cachyos` as 08-01 and 08-05.
6. Control test: cold power-off → boot macOS again: panel on iGPU in
   `system_profiler`, `gpu-policy %01` intact, `gpu-power-prefs` `%00%00%00%00`.

Interruption note: between steps 3 and 4 the machine was accidentally booted
into Limine's menu (no Linux kernel ran) and force-powered off; this did not
change any observed variable and macOS still came up on Intel afterward.

### 3. Interpretation

- Hypothesis (c) — a Linux boot destroys the variable — is **refuted**: the
  full Linux session left `gpu-policy %01` intact, and the next power-on
  honored it (for macOS).
- The remaining open question is narrowed to: with identical, verified NVRAM
  Intel state, why does a **macOS** power-on end with the panel on IGD while a
  **Linux** power-on leaves the mux on DIS? Two candidate mechanisms:
  1. macOS switches the mux at runtime (AGS is enabled: `pmset gpuswitch 0`),
     so "panel on Intel in macOS" may be a runtime switch rather than
     firmware state; Linux observes the firmware-left mux (DIS) at probe and
     never switches it (hard stop). Under this model the 08-01 Linux success
     remains the anomaly to explain.
  2. The firmware/bootloader distinguishes boot targets (Apple Set OS vs.
     macOS) when applying the policy.
- The gmux register state at the *end* of the last macOS session (before the
  power-off) was never recorded in any session; it is the one unobserved
  input. If the gmux register persists its position across the power cycle
  (battery-backed), the last-active-GPU in macOS could be the deciding input
  for the next Linux boot.

## What changed vs. earlier attempts

- A variable (`gpu-policy`) that survives and is honored was found; the
  assumed variable (`gpu-power-prefs`) is rewritten by macOS and is not
  listed by `nvram -p`.
- The control test closed hypothesis (c).
- The asymmetry (macOS Intel vs. Linux DIS from identical state) is now
  demonstrated with clean, verified inputs.

## Next experiment (single factor; do not combine)

**Track the gmux mux-register state through the macOS session end → cold
power-off → Linux boot transition** (mechanism 1 above):

- After the macOS session is confirmed on iGPU, check the register that
  `vga_switcheroo`/gmux reflects. macOS does not expose the gmux switch
  register directly; proxies: `ioreg -r -c AppleSMCPMU`/`AppleMuxControl` or
  `gpu-switch`'s readback; or end the macOS session with a forced discrete
  session first and see if the next Linux boot lands on DIS (which it does),
  then end with Intel and see if it lands on IGD — if Linux then lands on
  IGD, the deciding factor is the *last macOS-side mux position*, making the
  08-01-style sequence dependent on macOS AGS behavior at session end, not on
  the NVRAM variable.
- Control for the boot-target asymmetry: same register trace with a macOS
  power-on instead of Linux.

Alternative read if mechanism 2 is preferred: log whether macOS writes the
mux register only at runtime (AGS) or at shutdown, and whether the mux
position survives the power cycle (test: end macOS on DIS, cold off, boot
Linux, read switcheroo; end macOS on Intel, cold off, boot Linux, read
switcheroo — same variables, only the ending mux position differs).

## Checklist status

- [x] SMC reset (one deliberate, user-present)
- [x] Pref written and read back
- [x] Plain macOS reboot + survival check (failed for `gpu-power-prefs`, held for `gpu-policy`)
- [x] macOS session on iGPU confirmed before cold power-off
- [x] Cold power-off → UKI boot (mux DIS — E2 negative)
- [x] Control test: macOS returns on Intel; `gpu-policy` survives the Linux session

## References

- `docs/source-notes/2026-08-06-intel-panel-investigation-and-migration.md`
  (E2 design; hypotheses (a)/(b)/(c))
- `docs/source-notes/2026-08-05-intel-panel-path-retest.md` (negative retest)
- `docs/source-notes/2026-08-01-intel-panel-and-display-path.md` (positive)
