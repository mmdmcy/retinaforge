# Next Session Handoff

Last updated: 2026-08-05

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

## Graphics — current state (2026-08-05)

**Last proven Intel panel success:** 2026-08-01 (`i915drmfb`). See
`docs/graphics/intel-first-repro.md` and
`docs/source-notes/2026-08-01-intel-panel-and-display-path.md`.

**2026-08-05 retest:** same recipe (macOS Intel `gpu-power-prefs` + UKI) failed
to restore Intel eDP ownership. Nouveau remained primary; hybrid black-panel
recovered with GMUX backlight max + display-manager restart. Details:
`docs/source-notes/2026-08-05-intel-panel-path-retest.md`.

Do **not** burn another session on identical NVRAM + cold UKI loops. Next
graphics attempt must change one factor and get a user-present checkpoint.

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

1. Graphics: new single-factor attempt to restore Intel panel (not identical
   NVRAM+UKI repeat)—e.g. known Integrated-Only macOS tool, or kernel/UKI
   skew vs 2026-08-01—only with user checkpoint.
2. Reinstall to a current Fedora (or Debian + newer kernel); repeat
   `intel-first-repro.md` only after prefs/ownership strategy is clear.
3. Suspend/resume **after** Intel panel ownership is re-proven.
4. Native GT 750M outputs (separate from DisplayLink).
5. Storage flush-pattern follow-up only with an explicit checkpoint.

Default when unsure: leave APFS alone; read the 2026-08-05 retest note before
changing NVRAM or the bootloader.
