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

## Next test (single factor, one power cycle)

1. From the running Linux: power off; user holds Option at power-on → boot
   **macOS**.
2. Verify `pmset -g` shows `gpuswitch 2`; force a full session: `system_profiler`
   must show **NVIDIA** with the display attached (panel on DIS), not Intel.
   If the panel is still on Intel, wait/retrigger until the mux lands DIS,
   then confirm again.
3. **Cold power-off** (no reboot).
4. Power on **without** Option → Limine default entry 3 (UKI) → Linux.
5. Read `vga_switcheroo`: if `IGD:+` → the mux position at macOS power-down
   is the lever (recipe: end macOS on DIS before Linux boots); if `DIS:+`
   again → firmware lands Linux boots on DIS regardless of macOS-side state,
   leaving the 08-01 success as the single unexplained anomaly.

Checklist:
- [ ] macOS booted with `gpuswitch 2` verified
- [ ] Panel confirmed on DIS in `system_profiler` immediately before power-off
- [ ] Cold power-off, then plain power-on (no Option)
- [ ] UKI kernel confirmed (`uname -r` = 7.1.5-1-cachyos)
- [ ] `vga_switcheroo` readout recorded
- [ ] `check-intel-first-panel.sh` result recorded (if IGD)

## References

- `docs/source-notes/2026-08-07-e2-clean-slate-and-control-test.md`
- `docs/source-notes/2026-08-06-intel-panel-investigation-and-migration.md`
- `docs/source-notes/2026-08-05-intel-panel-path-retest.md`
- `docs/source-notes/2026-08-01-intel-panel-and-display-path.md`
