# Next Session Handoff

Last updated: 2026-08-08

Private operational checklist for agents working this repository's lab machine.
Public science and reproduction live in publishable docs under `docs/`. Do not
copy hostnames, addresses, keys, usernames, or conversation text into
publishable files.

## Machine layout (re-inventory before changes)

| Part | Role |
| --- | --- |
| sda1 | Apple EFI |
| sda2 | macOS APFS (preserve as recovery reference) |
| sda3 | Linux ESP / bootloader |
| sda4 | Linux root (ext4; currently CachyOS) |

Dual-boot remains. Do not shrink APFS or grow Linux without an explicit
user-present checkpoint and current backup policy.

## Storage track

Flush-pattern / AHCI diagnostic tooling is in-tree:

- `docs/flush-pattern-comparison.md`
- `patches/0002-ahci-mbp11-3-flush-reg-sample.patch`
- related `scripts/` and `tools/` probes and summarizers

Do not reopen physical storage boots without a fresh user-present checkpoint.
Writable MSI+NCQ remains forbidden.

## Graphics — current state (2026-08-07)

**Last proven Intel panel success:** 2026-08-01 (`i915drmfb`). See
`docs/graphics/intel-first-repro.md` and
`docs/source-notes/2026-08-01-intel-panel-and-display-path.md`.

**2026-08-05 retest:** same recipe (macOS Intel `gpu-power-prefs` + UKI) failed
to restore Intel eDP ownership. Nouveau remained primary; hybrid black-panel
recovered with GMUX backlight max + display-manager restart. Details:
`docs/source-notes/2026-08-05-intel-panel-path-retest.md`.

**2026-08-06 investigation:** upstream analysis shows the mux is decided by the
Apple EFI firmware at power-on; the `i915` eDP link-info error is the
ghost-panel path (mux left on discrete). Value semantics are correct;
persistence is the open variable. Kernel-skew (CachyOS → 7.1.x), firmware/SMC
state, or Linux destroying the variable are the ranked hypotheses. Details +
Debian/Mint migration plan:
`docs/source-notes/2026-08-06-intel-panel-investigation-and-migration.md`.

**2026-08-07 (E1 + E2 + control test):** E1 closed the kernel-skew gap — UKI
`cachyos-apple-set-os.efi` (built 08-01 12:27) embeds `7.1.5-1-cachyos`,
identical on success and failure. Full E2 (SMC reset → Intel prefs → plain
reboot survival check → iGPU session in macOS → cold off → UKI) **failed**:
mux `DIS:+` again. But the control test refuted hypothesis (c): macOS
returned on **Intel** and `gpu-policy %01` survived the Linux session.
Key discovery: on this machine + Big Sur the honored variable is
**`gpu-policy`** (no GUID, listed by `nvram -p`); `gpu-power-prefs` is
rewritten by macOS to discrete and is not listed by `nvram -p`. Same NVRAM
Intel state → macOS power-on = panel on IGD, Linux power-on = mux DIS; open
question is whether macOS switches the mux at runtime (AGS) or firmware
discriminates by boot target. Full record:
`docs/source-notes/2026-08-07-e2-clean-slate-and-control-test.md`.

Do **not** burn another session on identical NVRAM + cold UKI loops. Next
graphics attempt must change one factor and get a user-present checkpoint.
**Current open test (2026-08-08):** "macOS session ends on DIS → cold off →
UKI boot" — see `docs/source-notes/2026-08-08-limine-timeline-and-forced-dis-test.md`.
One power cycle, single factor; `gpuswitch 2` is set in macOS and must be
verified on the next macOS boot. Also recorded: Limine config was identical
across the 08-01 success and 08-05 retest (boot path ruled out), and the LTS
bare entry + proprietary nvidia driver is a working discrete fallback
desktop (no apple_set_os, no mux readout).

Daily usable path until re-proven: discrete/Nouveau desktop (hot). Optional:
set macOS prefs back to discrete `%00%00%00%00` for more predictable Linux
boots without the hybrid black-panel mode.

Restore recipe after reinstall (when Intel works again):

1. From macOS: `macos/scripts/set-gpu-power-prefs-intel.sh` (`%01%00%00%00`)
2. Boot Linux via UKI / EFI-stub (not bare `protocol: linux`)
3. On Linux: `scripts/graphics/check-intel-first-panel.sh` must pass
4. Optional: switcheroo `OFF` for the discrete client after IGD owns the panel
5. Never live-force GMUX / IGD mid-session

DisplayLink helpers (occasional presenting only):
`scripts/graphics/present-{on,layout,off}`. Sustained dual DisplayLink is hot.

Desktop note from lab: light X11 (e.g. Xfce) was stabler than heavy Plasma on
this multi-GPU setup; prefer the Intel DRM node when both GPUs enumerate **and**
Intel owns the panel.

## Distro note

The Intel-panel recipe is distro-agnostic. Prefer a **current** kernel with
EFI-stub/UKI boot (Fedora current, or Debian with a newer kernel/backports).
Validate with `check-intel-first-panel.sh` after any reinstall.

## In-repo vs recreate-on-install

**In repo:** intel-first repro docs/scripts, present helpers, storage flush
tooling and diagnostic patch.

**Recreate after wipe if needed:** SSH access, sudo policy, Wi-Fi, keymap,
optional always-on/lid policy, display manager/autologin, toolkit scale.

## Hard stops

- Writable MSI + NCQ: never for samples.
- No casual USB reprovision, repartition, or physical write tests without a
  fresh user-present checkpoint.
- Do not mix storage and NVIDIA/GMUX changes in one patch or experiment.
- No live GMUX / `force_igd` chasing after black panel; use recovery in
  `intel-first-repro.md` first.

## Access

Use the existing lab SSH key material and host known_hosts files already
configured for this workspace. The agent may reboot the Linux lab OS and
reconnect when that OS is the running system.

## Next experiments (pick one; do not combine)

1. **Distro migration (recommended):** Debian trixie (6.12) or Linux Mint 22.x
   (HWE 6.11) per the 2026-08-06 investigation note; rebuild EFI-stub/UKI
   entry; repeat `intel-first-repro.md`; record kernel version and UKI date.
   Primary goal is stability; re-ranked analysis says the failure is
   firmware-side (switcheroo `+` is gmux-register truth set before Linux
   boots), so migration is not expected to be the fix by itself. User checkpoint.
2. ~~E2 — clean-slate retry~~ — **RUN 2026-08-07, negative**: mux `DIS:+`
   despite SMC reset + verified Intel prefs; control test refuted
   hypothesis (c) (variable survives Linux; macOS returns on Intel). Next
   single-factor experiment: track the gmux/mux position through "end of
   macOS session → cold off → Linux boot" — end macOS on DIS vs. on Intel
   and see whether the next Linux boot's switcheroo state follows the
   last macOS-side mux position (see the 08-07 note, "Next experiment").
3. ~~Pin the 08-01 CachyOS kernel~~ — **DONE 2026-08-07**: UKI built
   2026-08-01 12:27, kernel `7.1.5-1-cachyos`, identical on success/failure.
4. Suspend/resume **after** Intel panel ownership is re-proven.
5. Native GT 750M outputs (separate from DisplayLink).
6. Storage flush-pattern follow-up only with an explicit checkpoint.

Default when unsure: leave APFS alone; read the 2026-08-06 investigation note
before changing NVRAM or the bootloader.
