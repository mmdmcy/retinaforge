# Limine Config Timeline, Unplanned LTS/nvidia Boot, and Forced-DIS Test Prep (2026-08-08)

## Abstract

Follow-up to the 2026-08-07 E2 run. This session (1) verified the Limine
config timeline from the Linux ESP, proving the boot path was **identical**
across the 08-01 success and the 08-05 retest; (2) accidentally produced a
Linux boot via the LTS `protocol: linux` entry with the **proprietary nvidia
driver** driving the panel on the DIS mux (a working discrete desktop,
documented as a fallback path); and (3) prepared the controlled
"macOS session ends on DIS → cold off → UKI boot" test, which was
contaminated when the macOS reboot landed in Linux instead of macOS.

## 1. Limine config timeline (evidence: ESP read-only mount from macOS)

The Linux ESP (sda3, vfat) was mounted read-only from macOS and the config
files compared. Menu order in Limine counts sub-entries (`//`) as menu
entries: linux-cachyos(0), linux-cachyos-lts(1), EFI fallback(2),
uki-apple-set-os(3).

| File | mtime | default_entry | remember_last_entry | entries |
| --- | --- | --- | --- | --- |
| `limine.conf` (current) | 2026-08-05 22:50 | 3 (UKI) | no | 4 |
| `limine.conf.bak-20260805-225026` | **2026-08-01 12:05** | 3 (UKI) | yes | 4 |
| `limine.conf.bak-before-uki` | 2026-08-01 11:05 | 2 | no | 2 |
| `limine.conf.bak-before-textmode` | 2026-08-01 10:57 | 2 | yes | 2 |
| `limine.conf.bak-pre-intel-default` | 2026-08-01 09:57 | 2 | no | 3 |
| `limine.conf.bak-macos-20260801105756` | 2026-08-01 01:20 | 2 | yes | 2 |
| `limine.conf.old` | 2026-08-01 10:47 | 3 | no | 3 |

**Conclusion:** the config saved as the 08-05 backup (mtime 08-01 12:05)
stayed in use from 08-01 12:05 until 08-05 22:50 — i.e. it was the active
config during the **08-01 14:05 success boot** and the entire **08-05
retest**. Default was the UKI entry in both eras, `remember_last_entry: yes`.
The boot path (Limine → same UKI `cachyos-apple-set-os.efi` → kernel
`7.1.5-1-cachyos`) was therefore identical across success and failure; the
bootloader is **not** the missing factor. Together with E1 (identical UKI/
kernel) this closes every Linux-side variable; only firmware/mux state at
power-on remains.

## 2. Unplanned LTS + proprietary nvidia boot (new fallback observation)

After `sudo shutdown -r now` from macOS (with `pmset -a gpuswitch 2` set
immediately prior), the machine came up in **Linux**: kernel
`6.18.40-1-cachyos-lts` via the bare `protocol: linux` entry, whose cmdline
lacks the nvidia blacklist (the UKI's cmdline has
`modprobe.blacklist=nvidia,…`; the bare entries do not). Consequences:

- The **proprietary nvidia driver (470.256.02)** loaded (nouveau and i915
  absent this boot; only `card1: nvidia` with `DP-2` = internal eDP at
  2880×1800).
- vga_switcheroo debugfs absent (nvidia driver does not register), i.e. no
  mux readout; panel is on the DIS mux as with every Linux boot.
- Working X11 desktop (sddm/Xfce), GPU idle 40 °C, backlight via
  `gmux_backlight`.
- This is a second usable discrete-desktop path (nvidia proprietary via the
  LTS bare entry) alongside the Nouveau desktop (UKI entry). Both are "hot"
  class; neither has Intel panel ownership.

Why the reboot selected the LTS entry instead of the default UKI is
unexplained (no Limine keypress observed; `remember_last_entry: no`). The
machine sat idle/off for an extended period between sessions (18+ h by wall
clock); treat any boot path outside "power-on → default entry 3" as
unexplained until evidence says otherwise. Noted for reproducibility: verify
the booted kernel (`uname -r`) before trusting which path ran.

## 3. Forced-DIS test — setup and contamination

Rationale (from the 08-07 note): only the mux position at the *end* of the
last macOS session is unobserved. macOS AGS may flip the gmux at shutdown
regardless of mid-session state, which would explain "verified Intel in
macOS, yet Linux boots DIS".

Attempted: `pmset -a gpuswitch 2` (force discrete) → reboot. **Contaminated:**
the reboot never ran macOS; it landed in Linux (see §2), so no
verified-mux-on-DIS macOS session preceded the Linux power-on. The gpuswitch
= 2 setting is expected to persist in macOS for the next attempt (verify
with `pmset -g` on the next macOS boot).

## Result (decisive negative)

Ran: macOS session with panel verified on **NVIDIA/DIS** (`gpuswitch 1` →
panel on GT 750M, Main Display on NVIDIA) → cold power-off → plain power-on
→ Limine → UKI entry selected → Linux `7.1.5-1-cachyos` →
`vga_switcheroo`: **`2:DIS:+:Pwr`**.

Combined with the 08-07 control test (macOS ended on **Intel**, verified →
cold off → UKI → also `DIS:+`), the mux outcome for a Linux UKI boot is now
shown **invariant to the mux position at the end of the preceding macOS
session**. Both end-states (Intel and discrete) yield `DIS` on the next
Linux boot. The mux-position-persistence hypothesis is **refuted**.

## Conclusion of the mux investigation

Every controlled Linux UKI boot since 08-01 has landed on `DIS`:
- 08-05 retest (same recipe, Intel pref)
- 08-07 E2 (SMC reset, `gpu-policy %01` + `gpu-power-prefs %01`, macOS on iGPU)
- 08-07 control boot (macOS on iGPU at end)
- 08-08 test (macOS on DIS at end)

while macOS power-ons from the same NVRAM state consistently honor the
policy (panel on Intel, or on NVIDIA per `gpuswitch`). The 08-01
`i915drmfb` success is the **single anomaly** with no reproduced factor;
the firmware effectively defaults non-macOS power-ons to the discrete side
on this machine, and no NVRAM/mux-position input changes that. The
remaining explanation space is a one-off firmware/SMC state (e.g. a
transient condition at that specific power-on) — not actionable via the
recipe, and not worth further identical loops.

## Bonus finding: `gpuswitch` values are inverted on this machine

`pmset -g` semantics observed empirically (MBP11,3, Big Sur 11.7.11):
- `gpuswitch 1` → panel on **NVIDIA** (discrete)
- `gpuswitch 2` → panel on **Intel** (integrated)

Opposite of the commonly documented mapping (1 = integrated, 2 =
discrete). Verified on two separate boots. This does not affect the Linux
side (Linux does not read `gpuswitch`), but it matters for anyone setting
macOS-side policy.

## Practical outcome for the lab

- The repeatable, stable Linux state is the **discrete desktop**: UKI entry
  (nouveau) or LTS bare entry (proprietary nvidia 470). Both work at
  2880×1800; panel mux DIS; idle GPU ~40 °C.
- Intel panel ownership under Linux is not reachable through NVRAM/mux
  state levers on current firmware behavior; treat the 08-01 success as
  unreproduced until a new factor appears.
- For "proper" daily stability, the E4 migration (Debian trixie 6.12 or Mint
  22.x, EFI-stub/UKI boot) remains the recommended operational change; it
  will NOT by itself restore Intel panel ownership.

## Next test (single factor, one power cycle)

(original plan — superseded by the result above; kept for the record)


## References

- `docs/source-notes/2026-08-07-e2-clean-slate-and-control-test.md`
- `docs/source-notes/2026-08-06-intel-panel-investigation-and-migration.md`
- `docs/source-notes/2026-08-05-intel-panel-path-retest.md`
- `docs/source-notes/2026-08-01-intel-panel-and-display-path.md`
