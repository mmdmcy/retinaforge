# Next Session Handoff

Last updated: 2026-08-16 — **session wrapped; AGS-vs-Linux written down**

## Session wrap (2026-08-16)

OpenCode GPT-5.6 work on this tree from 2026-08-10 through 2026-08-13 is now
in git. Goal remains **Intel i915 desktop on the internal panel**. A sale /
triple-boot listing detour on 2026-08-13 was abandoned the same day; keep the
machine as the lab.

**Left on disk (Linux, last confirmed 2026-08-13 evening):**

- Limine **default** = `RetinaForge NVIDIA LTS` (`6.18.40-1-cachyos-lts`,
  NVIDIA 470, Plasma X11, panel 2880×1800). This is the SSH recovery desktop.
- Manual menu: `RetinaForge Intel historical baseline` (byte copy of the
  08-01 success UKI) and the newer `force_igd` Intel UKI. Neither is default.
- 2026-08-13 historical-UKI retest **failed** even after verified macOS
  `gpu-policy=%01` + Intel `gpu-power-prefs` + cold off. See
  `docs/source-notes/2026-08-13-historical-uki-retest.md`.
- eDP-handoff profile is **opt-in only** and must stay off the default boot
  (wedges SSH). `enable-intel-daily.sh` disables that unit.

**Reachability at wrap (2026-08-16):** `mbp113-linux` last seen ~2 days ago
on the tailnet; `mbp113-macos` LAN SSH timed out. Assume the lab laptop is
powered off or asleep until a physical power-on. Do not reboot it blindly
from another device.

| Doc | Contents |
| --- | --- |
| `docs/source-notes/2026-08-10-uki-intel-attempt-and-xorg-fail.md` | `force_igd` breakthrough, 0 DRM modes, Xorg fail |
| `docs/source-notes/2026-08-10-edp-handoff-research.md` | DIS-first handoff v1–v3, `NEEDS_EDP_CONFIG`, boot wedge |
| `docs/source-notes/2026-08-13-historical-uki-retest.md` | 08-01 UKI + verified NVRAM still ghost-panel |
| `docs/graphics/why-not-macos-ags.md` | Why Linux cannot copy Big Sur AGS on this GMUX |
| `scripts/graphics/enable-intel-daily.sh` | Default Intel path (`force_igd`; handoff off) |
| `scripts/graphics/enable-intel-edp-handoff.sh` | Opt-in handoff profile only |
| `scripts/graphics/retinaforge-keep-display-awake.sh` | X11 DPMS helper (user `XAUTHORITY`, not SDDM’s) |

**Resume (one variable):** power on → confirm NVIDIA LTS still default →
**do not** repeat historical UKI + NVRAM. Next Intel work is the `force_igd`
0-modes gap, or a user-present distro/kernel isolation. Keep NVIDIA LTS as
fallback. Do **not** start a macOS-style dual-GPU switching project; that is
out of scope until Intel panel ownership is repeatable. Why:
[`docs/graphics/why-not-macos-ags.md`](graphics/why-not-macos-ags.md).

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

## Primary goal

**Intel i915 desktop on the internal Retina panel** — daily driver target for
this lab. Discrete/NVIDIA paths exist only as **emergency SSH recovery** when
Intel work bricks the local display; they are not the product goal and agents
must not steer the user toward them unless explicitly asked.

## Known-good emergency recovery (not the goal)

If Intel experiments leave no local display but SSH still works:

- Limine → `linux-cachyos-lts` after `disable-nvidia-off.sh` (proprietary
  nvidia 470 on DIS mux). Use only to regain a console for more Intel work.
- macOS remains the recovery reference for NVRAM writes and firmware state.

## Daily stable recipe (verified 2026-08-08) — emergency reference only

**Discrete NVIDIA desktop (SSH recovery path, not target state):**

- Boot → Limine → LTS bare entry (`6.18.40-1-cachyos-lts`) with the
  proprietary nvidia driver (470.256.02) driving the panel on the DIS mux at
  2880×1800; mux `DIS` is deterministic for every Linux bare boot.
- `scripts/graphics/gmux-backlight-max.service` (installed at
  `/etc/systemd/system/`, enabled) forces `gmux_backlight` to 1023 at boot —
  kills the recurring black screen. Pair with
  `gmux-backlight-max-session.service` and
  `scripts/graphics/install-gmux-backlight-fix.sh` so Xfce does not dim the
  panel after login. Reinstall if recreated.
- Intel experiments: `mbp-cool-idle.service` disabled (vgaswitcheroo OFF + lid
  blank; not the ~6s eDP failure, but removed as a variable).
- Note: verify boot path with `uname -r` and StubInfo before trusting results.
- macOS stays the recovery reference.

**UKI / Intel daily path (2026-08-10, updated evening):**

- In-tree stack: `enable-intel-daily.sh`, `build-apple-set-os-uki.sh`,
  `limine-set-default-uki.sh`, `verify-intel-uki-boot.sh`.
- **Breakthrough:** `apple_gmux.force_igd=1` on UKI + `MODULES=(apple-gmux
  i915)` → `Switching to IGD`, eDP-1 **connected**, no link-info fail.
- **Still open:** kernel DRM **0 modes** on eDP-1; Xorg `failed to set mode`;
  black panel, backlight max. Not `i915drmfb` yet.
- macOS `gpu-policy %01` before cold off still reads `%00` on Linux early boot;
  `force_igd` bypasses GMUX but prefs may still matter for full modeset.
- Full record: `docs/source-notes/2026-08-10-uki-intel-attempt-and-xorg-fail.md`.
- Do **not** re-enable `retinaforge-nouveau.service` on nvidia-off path.

**eDP handoff profile (2026-08-10 evening, new):**

- New scripts: `enable-intel-edp-handoff.sh`, `gmux-edp-handoff.sh`,
  `mkinitcpio-intel-handoff-uki.conf`, `INTEL_UKI_PROFILE=handoff` in UKI build.
- Theory: indexed GMUX `NEEDS_EDP_CONFIG` — nouveau must train eDP on DIS before
  IGD switch; `force_igd` skips that step.
- **v1/v2 boot results:** nouveau gets 10 DRM modes on DIS; switcheroo reaches
  `IGD:+`; i915 still `failed to retrieve link info` / 0 modes. Panel stayed on
  `nouveaudrmfb` in v2.
- **v3 (disable_display handoff):** script updated but deploy/reboot lost SSH
  (`mbp113-linux` unreachable via Tailscale after reboot ~19:54 UTC). Machine may
  need manual power-on or hung on boot — check when back on LAN.
- **2026-08-10 23:00:** Handoff **removed** from default boot (wedges SSH). Stable
  session: `enable-intel-daily.sh` + `force_igd` UKI rebuilt on disk
  (`apple_gmux.force_igd=1` confirmed in EFI image). Current live boot still old
  handoff cmdline until next reboot; panel on **nouveau** (11×2880×1800 modes),
  i915 inactive with `failed to retrieve link info` when loaded on DIS.
- Research doc: `docs/source-notes/2026-08-10-edp-handoff-research.md`.
- Revert to force_igd profile: `enable-intel-daily.sh` +
  `INTEL_UKI_PROFILE=force_igd build-apple-set-os-uki.sh`.

**Historical UKI retest (2026-08-13, negative):**

- Daily Linux restored to NVIDIA LTS + Plasma X11 before the test.
- Historical 08-01 UKI installed as a **manual** Limine entry
  (`cachyos-intel-historical-baseline.efi`, SHA-256
  `24e1fca10c8a7237b8e83fc74de22bc0be3d76bb17366d5329f78c823fcc0dea`).
- macOS wrote and read back `gpu-policy=%01` and Intel `gpu-power-prefs`,
  then cold off. Historical UKI boot: `i915` loaded, eDP disabled for
  link-info, `simpledrm` primary, NVIDIA loaded anyway. SSH survived.
- Restored NVIDIA LTS default. Full record:
  `docs/source-notes/2026-08-13-historical-uki-retest.md`.
- KDE DPMS needed a keep-awake helper using the user X auth file; a later
  full-machine drop-off was likely **sleep**, not panel blanking.

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
**Mux investigation CLOSED 2026-08-08 (negative):** the forced-DIS test
(macOS session verified ending on NVIDIA → cold off → UKI → still `DIS:+`)
completed the pair with the 08-07 Intel-ended control; Linux UKI boots land
on DIS regardless of NVRAM state or the preceding macOS mux position. The
08-01 `i915drmfb` success is the single unreproduced anomaly. Also recorded:
Limine config identical across 08-01 success and 08-05 retest (boot path
ruled out); `gpuswitch 1` = discrete, `2` = integrated on this machine
(inverted from common docs); LTS bare entry + proprietary nvidia 470 is a
working discrete fallback. Repeatable stable state = discrete desktop (UKI
+ nouveau, or LTS + nvidia). Full record:
`docs/source-notes/2026-08-08-limine-timeline-and-forced-dis-test.md`.

Daily usable path until Intel is re-proven: continue Intel-first experiments.
Do not recommend discrete desktop as a substitute unless the user explicitly
asks for recovery or SSH is blocked.

Restore recipe when Intel panel works:

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
- No live GMUX handoff mid-session. Boot-time `apple_gmux.force_igd=1` on the
  UKI path is **in scope** (see 2026-08-10 note); do not stack other variables
  in the same reboot without recording them.

## Access

Use the existing lab SSH key material and host known_hosts files already
configured for this workspace. Prefer the fleet names in
[`docs/fleet-naming.md`](fleet-naming.md): `neo` (controller Mac),
`mini` and `Sparta` (additional controllers), `mbp113-linux` (CachyOS lab
OS), `mbp113-macos` (Big Sur on the same hardware). Only one lab OS is
reachable at a time. Linux is Tailscale MagicDNS; macOS SSH in this fleet
is the LAN/mDNS alias. The agent may reboot the Linux lab OS and reconnect
when that OS is the running system. Do not copy key material into git.

## Next experiments (pick one; do not combine)

0. **Intel daily desktop (primary goal)** — `force_igd` UKI path already
   gets eDP **connected** with 0 DRM modes. Next: one-at-a-time i915 cmdline
   / PC8 / initramfs-firmware diff. Keep NVIDIA LTS as Limine default.
0b. **Boot automation** — `limine-set-default-uki.sh` (flat entry 1, 5s) only
    after `check-intel-first-panel.sh` passes.
1. ~~UKI nvidia-off rebuild~~ — **DONE 2026-08-10** (`build-apple-set-os-uki.sh`).
2. ~~In-tree verify script~~ — **DONE** (`verify-intel-uki-boot.sh`).
3. **DRM modes on eDP-1** — remaining `force_igd` gap (see 08-10 UKI note).
4. ~~E2 — clean-slate retry~~ — **RUN 2026-08-07, negative** (see 08-07 note).
5. ~~Pin / retest the 08-01 UKI~~ — **RUN 2026-08-13, negative** (see 08-13 note).
6. Suspend/resume **after** Intel panel ownership is re-proven. Current NVIDIA
   session can still sleep the whole machine; that is not an Intel experiment.
7. Native GT 750M outputs (separate from DisplayLink).
8. Storage flush-pattern follow-up only with an explicit checkpoint.
9. ~~Indexed eDP handoff as default boot~~ — **tried 2026-08-10, do not
   re-enable on default** (SSH wedge). Opt-in profile only.

Default when unsure: leave APFS alone; read the 2026-08-06 investigation note
before changing NVRAM or the bootloader.
