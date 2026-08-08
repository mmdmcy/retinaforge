# MacBookPro11,3 Intel Panel Path — Investigation and Distro Migration (2026-08-06)

## Abstract

Sequel to the failed 2026-08-05 retest. Upstream-source investigation
(kernel `apple-gmux` and `i915` docs, `0xbb/gpu-switch`) shows that on this
machine the panel mux decision is made by the **Apple EFI firmware at
power-on** from `gpu-power-prefs`; Linux can only observe the outcome.
The 2026-08-05 failure therefore happened **upstream of the kernel**: the
firmware left the mux on the discrete side (`DIS:+:Pwr` in switcheroo is the
gmux register truth), and `i915`'s "failed to retrieve link info, disabling
eDP" is the documented ghost-panel path when the eDP AUX/main link is muxed
to the other GPU. The lab's `%01%00%00%00` value is correct (identical to the
canonical `gpu-switch` value for this exact model); persistence across
OS round-trips is the open variable.

**Hypotheses re-ranked on re-examination (2026-08-06, post-release):** the
retest's own evidence largely **refutes** the kernel-skew hypothesis — the
switcheroo `+` marker is gmux-register truth set by firmware at power-on,
and nothing in `apple-gmux` writes the switch state during boot (verified:
`gmux_switchto` is only reachable via explicit switcheroo commands), so no
kernel version could have changed the mux position. The failure is therefore
firmware-side with near-certainty; ranked causes: (1) the firmware did not
apply/consume the pref at the 08-05 power-ons (variable loss between the
macOS write and the next power-on, or macOS rewriting it), (2) firmware/SMC
state-machine behavior (the hybrid black-panel mode — Intel-oriented
framebuffer allocated while the panel stayed on DIS — hints at a
firmware-internal inconsistency), (3) Linux boot destroying the variable so
later attempts start from discrete. The 08-01 recipe is still valid — the
retest's own session 5 proves the firmware can still honor the pref (panel
on iGPU in macOS) — so the primary fix attempt is a **clean-slate retry**
(E2): one deliberate SMC reset, then the strict 08-01 sequence with the
pref-survival and macOS-control checks added; the 08-05 runs are treated as
contaminated after the first failure. The distro migration below is a
stability fix and a clean single-factor change, **not** expected to be the
fix by itself. Because CachyOS proved too unstable for daily use, migration
to **Debian (trixie/backports) or Linux Mint (22.x)** is planned regardless;
6.1/6.8/6.11/6.12 kernels also predate the suspect 7.1.x line, so the
migration still answers the kernel question as a side effect. The Intel-first
recipe itself is distro-agnostic.

Note: the 2026-08-01 success note did **not** record the kernel version or
UKI build date — a data gap that kept the kernel-skew question open in the
repo. **Resolved 2026-08-07 (E1):** the UKI `cachyos-apple-set-os.efi` on
the CachyOS ESP was built 2026-08-01 12:27 CEST and embeds kernel
`7.1.5-1-cachyos` (built 2026-07-27); its mtime was unchanged through the
08-05 retest, and the 08-01 success session journal (`-11`) prints the same
`7.1.5-1-cachyos` in its last kernel trace. The kernel binary was therefore
**identical** across the 08-01 success and the 08-05 failure, fully closing
the kernel-skew hypothesis; the failure is firmware-side, as concluded
above.

## Context

| Item | Value |
| --- | --- |
| Model | `MacBookPro11,3` (Iris Pro `8086:0d26` + GT 750M `10de:0fe9` + Apple GMUX) |
| Prior success | 2026-08-01 (`i915drmfb`, eDP 2880×1800) |
| Failed retest | 2026-08-05 (same recipe; Nouveau primary, `i915` eDP link-info failure) |
| Reference OS | macOS Big Sur (APFS preserved) |
| Current Linux lab | CachyOS (rolling; kernel in the 7.1.x era at retest) |
| Candidate migration | Debian (trixie 6.12 or bookworm 6.1 + backports) / Linux Mint 22.x (6.8, HWE 6.11) |

Related:

- [`2026-08-05-intel-panel-path-retest.md`](2026-08-05-intel-panel-path-retest.md)
- [`2026-08-01-intel-panel-and-display-path.md`](2026-08-01-intel-panel-and-display-path.md)
- [`../graphics/intel-first-repro.md`](../graphics/intel-first-repro.md)

## Mechanism (upstream research, verified 2026-08-06)

### 1. The mux is a firmware-time decision, not a kernel decision

Kernel `apple-gmux` driver documentation
(`drivers/platform/x86/apple-gmux.c`, `DOC: Graphics mux`):

> gmux' initial switch state on bootup is user configurable via the EFI
> variable `gpu-power-prefs-fa4ce28d-…` (5th byte, 1 = IGD, 0 = DIS). Based
> on this setting, the EFI firmware tells gmux to switch the panel and the
> external DP connector and allocates a framebuffer for the selected GPU.

So the hardware switch happens **before any OS runs**. Linux inherits it.
The retest's `DIS:+:Pwr` switcheroo state is a readout of the gmux switch
registers, i.e. physical truth at Linux probe: on 2026-08-05 the panel was
on the discrete side despite the verified Intel pref.

### 2. `gpu-power-prefs` value semantics are correct

`0xbb/gpu-switch` — the canonical community tool, which lists
`MacBookPro 11,3` as tested hardware — writes the efivarfs file as
4-byte attribute header (`07 00 00 00`) + data bytes `01 00 00 00` for
integrated, `00 00 00 00` for discrete. The kernel doc's "5th byte" counts
the attribute header, so the first **data** byte is the switch bit — the
lab's macOS value `%01%00%00%00` is byte-for-byte the same. Value semantics
are **not** the problem; persistence and firmware consumption are.

### 3. The i915 error is the ghost-panel path, not an i915 bug

In current `i915` (`drivers/gpu/drm/i915/display/intel_dp.c`,
`intel_edp_init_connector()`):

- `intel_edp_init_dpcd()` reads the panel's DPCD over AUX; on retina Macs the
  eDP AUX/main link is muxed (the retina mux chips cannot switch AUX
  separately), so when the mux is on the discrete side the AUX read fails.
- Failure of that read takes the documented branch:
  `"[ENCODER:%d:%s] failed to retrieve link info, disabling eDP\n"` with the
  comment "if this fails, presume the device is a ghost".
- `i915` does defer its probe until `apple-gmux` is present
  (`vga_switcheroo_client_probe_defer()` in `intel_display_driver.c`,
  "apple-gmux is needed on dual GPU MacBook Pro to probe the panel if we're
  the inactive GPU") — but nothing in the kernel *switches* the mux.

**Conclusion.** The 2026-08-05 symptom chain (switcheroo `DIS:+`, Nouveau
primary fb, i915 eDP link-info failure) is fully explained by "firmware left
the mux on DIS at power-on". The failure is upstream of the kernel.

### 4. There is no kernel-side mux lever left

- Mainline `apple-gmux` has **no** `force_igd` / `force_disd` module
  parameters — verified absent in v6.1, v6.6, v6.12, v7.0 and master.
- The t2linux `options apple-gmux force_igd=y` mechanism applies to T2 Macs
  with the t2linux patched kernel line; not available here.
- Live sysfs / switcheroo IGD forcing remains the documented black-screen
  path and stays a hard stop.

### 5. Persistence is the real open variable

- macOS rewrites `gpu-power-prefs` on its own boots according to its current
  graphics policy — consistent with the retest's "prefs often read back as
  discrete (`%00%00%00%00`) on later macOS visits".
- Linux efivarfs exposes Apple variables as unreadable stubs (EINVAL),
  reconfirmed on 08-05; Linux is not a reliable writer *or* reader of this
  variable. Whether a Linux boot can *destroy* the variable is unproven but
  is the leading suspect for the observed round-trip loss.

## Findings (decided)

1. **Mux side is decisive.** The `i915` eDP link-info error is a symptom of
   "panel on the other GPU", not a driver regression candidate by itself.
2. **The value is right; persistence is the open variable.** A verified
   macOS readback at time T does not guarantee the firmware consumed an Intel
   policy at the next power-on.
3. **Only the Linux-side switcheroo `+` is evidence.** macOS readback,
   `system_profiler` active-GPU, and `pmset` locks are session-level facts,
   not next-boot mux policy.
4. **The failure is firmware-side with near-certainty; kernel skew is
   largely refuted.** The switcheroo `+` is gmux-register truth written by
   the EFI firmware at power-on; `apple-gmux` never writes the switch state
   during boot (`gmux_switchto` is reachable only through explicit
   vga_switcheroo switch commands), so no kernel version can change the mux
   position. The remaining questions are *why* the firmware left the mux on
   DIS despite a verified Intel pref: (a) the pref was lost or rewritten
   between the macOS write and the next power-on, (b) firmware/SMC
   state-machine behavior (the hybrid black-panel mode, where the firmware
   allocated an Intel-oriented framebuffer while the panel stayed on DIS,
   hints at firmware-internal inconsistency), (c) a Linux boot destroyed the
   variable for subsequent power-ons. `i915` DP/eDP code churn (~170 commits
   in `intel_dp.c` since 2025-01) is a red herring for this symptom; it
   remains relevant only after the mux is provably on the IGD side again.
5. **The firmware can still honor the pref — there is a fix.** The retest's
   own session 5 proves the power-on sequence switched the panel to IGD in
   macOS (Intel as active panel owner in `system_profiler`) with the same
   pref value. The 08-01 recipe is therefore still valid; what broke is one
   of its inputs. Leading suspect: **contamination** — the first failed
   08-05 boot (or a Linux boot stubbing/destroying the variable) poisoned
   every later attempt, so all subsequent power-ons started from a dirty
   state. A clean-slate reset plus the strict 08-01 sequence is the primary
   fix attempt (E2 below), not a last resort.

## Solution path (single-factor experiments; user-present checkpoints only)

### E2 — Clean-slate retry of the exact 08-01 recipe (primary fix attempt)

**RESULT 2026-08-07: negative; control test refuted hypothesis (c).** Full
run with SMC reset, byte-verified Intel `gpu-policy %01` + `gpu-power-prefs`
`%01%00%00%00`, and macOS on iGPU immediately before cold power-off still
came up `DIS:+` on the UKI boot; a subsequent macOS power-on returned on
Intel with the variables intact. New finding: the honored variable on this
machine/Big Sur is `gpu-policy` (see
[`2026-08-07-e2-clean-slate-and-control-test.md`](2026-08-07-e2-clean-slate-and-control-test.md)).

The 08-05 attempts deviated from the 08-01 sequence (extra macOS sessions
between write and boot, `pmset` forcing) and, after the first failure, ran
from a contaminated state. Restore the known-good state first, then mirror
the 08-01 boot order exactly:

0. **SMC reset first** (the "un-stick" step, not a last resort): clears
   NVRAM and resets the mux state machine to its default. User-present,
   documented hard stop on casual resets — this is a deliberate one-time
   reset before the fix attempt.
1. Fresh macOS session (no Linux in between): write Intel pref
   (`set-gpu-power-prefs-intel.sh`), verify readback (`nvram -p` and
   `nvram -x` for exact bytes).
2. **Plain macOS reboot (no Linux), then read the pref again.** If it
   survives, macOS is not rewriting it and the variable persists in the
   firmware store. If it flips to discrete, macOS policy (AGS / `gpuswitch`)
   is the rewritter — fix that setting first, then repeat step 1.
3. Confirm the *panel* is genuinely on the iGPU in `system_profiler`
   (proves the power-on sequence honored the pref).
4. **Immediately cold power-off** (not soft reboot), then boot the Linux
   UKI — no extra macOS sessions, no `pmset` fiddling, matching the 08-01
   boot order byte-for-byte.
5. On Linux: `check-intel-first-panel.sh` must pass; record fb name, eDP
   status, switcheroo dump.
6. After every Linux boot, re-check the variable on macOS. If gone/stubbed,
   that Linux boot destroyed it → every subsequent attempt started from
   discrete; log this.

**Control test (if E2 still fails):** after a macOS-on-iGPU session with a
verified pref, cold power-off and boot **macOS again** (not Linux). If
macOS itself comes back on DIS, the firmware flipped on its own — conclusive
that Linux played no part, and the SMC/EFI state machine is the remaining
target (repeat step 0 before judging a second time).

### E1 — Pin the 08-01 kernel (supporting data, not a primary lever)

**DONE 2026-08-07.** The 08-01 note did not record the kernel version or
UKI build date; recovered from the CachyOS ESP (`/boot/EFI/Linux/`, limine
config backups) and journal before any erase: UKI built 2026-08-01 12:27,
embedded kernel `7.1.5-1-cachyos`; the same UKI was used for the 08-05
retest, so kernel identity is ruled out as the success/failure variable.
Pinning that kernel + UKI and repeating the recipe would now be redundant;
skip it. (Secondary observation: the 08-01 success session journal ends at
17:22 with a shutdown-time Xorg warning trace on the same kernel, no crash.)

### E3 — SMC reset (only if E2 cannot be satisfied)

User-present, documented hard stop on casual resets; clears NVRAM, so
re-do the macOS write cycle afterward.

### E4 — Distro migration (stability fix + single-factor change)

See below. Not expected to be the fix by itself; it answers the kernel
question only as a side effect and is primarily justified operationally
(CachyOS instability).

## Debian / Linux Mint migration plan

### Why

- CachyOS (rolling) instability is operational: frequent kernel/lib updates
  and ABI churn confound graphics experiments and make the machine unfit for
  daily use.
- A stable distro pins the kernel variable. Debian bookworm (6.1 LTS),
  Debian trixie (6.12), Linux Mint 22.x (Ubuntu 24.04 base; 6.8, HWE 6.11)
  all predate the 7.1.x era — a side-effect check on the (now largely
  refuted) kernel-skew hypothesis, not the primary motivation.
- The Intel-first recipe is distro-agnostic (`docs/graphics/intel-first-repro.md`).

### Requirements

- **Preserve macOS (APFS)** — unchanged policy.
- Install on a separate partition/disk; plain ext4 is enough for graphics
  lab work.
- Keep AHCI MSI+NCQ writable experiments out of this track entirely
  (both distros use the same `144d:1600` controller; policy unchanged).
- **EFI-stub/UKI boot is mandatory** (Apple Set OS). GRUB `linux` protocol
  does **not** run Apple Set OS on this machine (2026-08-01 evidence).
  Working options:
  - systemd-boot + a UKI built with `kernel-install` / `ukify`
    (Debian trixie and Mint 22.x ship these; package `systemd-ukify`);
  - GRUB `chainloader` of the UKI (loads it as an EFI app — equivalent to
    Limine `protocol: efi`, so Apple Set OS runs) — easiest Debian-native
    option if the installer set up GRUB;
  - keep Limine with a `protocol: efi` entry pointing at the UKI, as today.
- Ensure `i915` and `apple-gmux` are in the initramfs; `i915` defers its
  probe until `apple-gmux` is present (vga_switcheroo), so gmux must load
  early.
- macOS remains the only supported writer of `gpu-power-prefs`
  (`macos/scripts/set-gpu-power-prefs-intel.sh`).
- `scripts/graphics/check-intel-first-panel.sh` remains the acceptance gate.

### Kernel choice

| Distro | Kernel | Note |
| --- | --- | --- |
| Debian bookworm (12) | 6.1 LTS | Adequate (Apple product-name support since 5.16); if it fails, try backports before concluding |
| Debian trixie (13) | 6.12 | Recommended default; closest pinned kernel to the 08-01 era |
| Linux Mint 22.x | 6.8 / HWE 6.11 | Recommended if the operator wants Ubuntu LTS tooling + GUI installers |

Recommendation: **Debian trixie (6.12) or Mint 22.x (HWE 6.11)** as the
primary candidates; record `uname -r` and the UKI build date in the session
note, and cross-reference the 08-01 kernel version (E1) before choosing.

### Steps

1. Recover/record the 08-01 CachyOS kernel version (E1) before wiping.
2. Install Debian or Mint on the Linux partition (preserve macOS/APFS).
3. Build the EFI-stub/UKI entry (options above); keep a nomodeset fallback.
4. Repeat `intel-first-repro.md` Steps A–C:
   - macOS: Intel pref write + readback;
   - full power-off (cold), then UKI boot;
   - Linux: `check-intel-first-panel.sh` must pass; record fb name, eDP
     status, switcheroo dump, package temp.
5. Re-check the pref on macOS after the Linux session; log persistence.
6. Do not combine with any other experiment (suspend/resume, native GT 750M
   outputs, storage) until Intel panel ownership is re-proven.

### Migration caveats

- If 6.1 (bookworm) reproduces the failure, do **not** conclude "stable
  kernel fails too" — retry with the trixie/backports kernel before judging.
- Mint/Ubuntu ship `linux-firmware` and Nouveau — fine for the discrete
  fallback desktop; keep the light X11 (Xfce) preference from the lab notes.
- The CachyOS distro-specific UKI does not transfer; rebuild one for the new
  distro (ukify/objcopy stub) or reuse Limine `protocol: efi`.

## Non-goals / not claimed

- No claim that the 2026-08-01 success was mistaken, and no claim that a
  distro migration restores Intel ownership by itself — the failure is
  firmware-side with near-certainty, and the firmware is only reachable
  through the macOS write + power-on sequence (E2).
- No claim that the firmware is "broken": session 5 of the retest shows the
  power-on sequence can still honor the pref; the open question is which
  recipe input changed, with contamination after the first failed boot as
  the leading suspect.
- No root-cause isolation between firmware, SMC, and NVRAM consumers
  (requires the E2 diagnostics above).
- No endorsement of Linux efivarfs writes for this variable (reconfirmed
  stub behavior; macOS stays the writer).
- No `force_igd` hunting on mainline (does not exist there).
- No storage or MSI+NCQ results.

## Implications

1. Do **not** repeat identical NVRAM + UKI loops on CachyOS: both the retest
   and this analysis say the lever is firmware-side, and CachyOS's rolling
   kernel churn confounds the measurement.
2. E2 is the primary fix attempt: one deliberate SMC reset to a clean slate,
   then the strict 08-01 sequence (write → verify → plain macOS reboot →
   pref survival check → iGPU session → immediate cold power-off → UKI).
   It turns the opaque firmware step into verifiable facts.
3. After the first failed attempt, every later power-on ran from a
   contaminated state; treat 08-05 as invalid for judging the recipe itself.
4. Prefer E4 (migration) for daily-use stability; treat it as a clean
   single-factor change, not as the expected fix.
5. Only the Linux switcheroo `+` state after a UKI boot counts as evidence
   of Intel panel ownership; macOS-side verification alone is insufficient.
6. Keep the black-panel recovery playbook (backlight max + display-manager
   restart; never live GMUX force) for the hybrid failure mode during any of
   the experiments.

## Reproducibility checklist (for the E2 fix attempt and migration pass)

- [x] 08-01 CachyOS kernel version recovered (UKI `cachyos-apple-set-os.efi` built 2026-08-01 12:27, kernel `7.1.5-1-cachyos`; same UKI on 08-05) — E1 complete, 2026-08-07
- [ ] **E2 step 0:** one deliberate SMC reset (user-present) to a clean slate
- [ ] E2 step 2: pref survives a plain macOS reboot (else fix AGS/`gpuswitch` policy first)
- [ ] macOS readback of Intel `gpu-power-prefs` immediately before power-off
- [ ] macOS session on iGPU confirmed in `system_profiler` before cold power-off
- [ ] Cold power-off then UKI boot — no intervening macOS sessions, no `pmset` fiddling
- [ ] Control test if E2 fails: macOS-on-iGPU session → cold power-off → boot macOS again; log which GPU macOS comes back on
- [ ] Distro + kernel version and UKI build date recorded (migration pass)
- [ ] UKI/EFI-stub entry confirmed (`protocol: efi` / chainloader / systemd-boot)
- [ ] `i915` + `apple-gmux` present in initramfs
- [ ] fb name, eDP status, switcheroo dump, package temp recorded
- [ ] `check-intel-first-panel.sh` passes before claiming success
- [ ] Pref re-checked on next macOS boot (persistence; log if Linux stubbed it)
- [ ] Preserve APFS; no MSI+NCQ writable trials; no other experiments combined

## References (in-repo and upstream)

- `docs/source-notes/2026-08-05-intel-panel-path-retest.md` (negative retest)
- `docs/source-notes/2026-08-01-intel-panel-and-display-path.md` (positive)
- `docs/graphics/intel-first-repro.md` (recipe; Steps A–C)
- Linux `drivers/platform/x86/apple-gmux.c` — `DOC: Graphics mux` (firmware
  switch + efivarfs attribute layout; retina AUX/mux facts)
- Linux `drivers/gpu/drm/i915/display/intel_dp.c` — `intel_edp_init_dpcd()`
  and the "failed to retrieve link info, disabling eDP" ghost-panel path
- Linux `drivers/gpu/drm/i915/display/intel_display_driver.c` — i915 probe
  deferral until apple-gmux
- `https://github.com/0xbb/gpu-switch` — canonical `gpu-power-prefs` writer;
  tested hardware list includes MacBookPro 11,3
- t2linux wiki hybrid-graphics guide — `force_igd=y` context (T2/patched
  kernels only; not applicable here)
