# Next Session Handoff

Last updated: 2026-08-01

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

## Graphics — restore after any Linux reinstall

Follow `docs/graphics/intel-first-repro.md`:

1. From macOS: `macos/scripts/set-gpu-power-prefs-intel.sh` (`%01%00%00%00`)
2. Boot Linux via UKI / EFI-stub (not bare `protocol: linux`)
3. On Linux: `scripts/graphics/check-intel-first-panel.sh`
4. Optional: switcheroo `OFF` for the discrete client after IGD owns the panel
5. Never live-force GMUX / IGD mid-session

DisplayLink helpers (occasional presenting only):
`scripts/graphics/present-{on,layout,off}`. Sustained dual DisplayLink is hot.

Desktop note from lab: light X11 (e.g. Xfce) was stabler than heavy Plasma on
this multi-GPU setup; prefer the Intel DRM node when both GPUs enumerate.

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

## Access

Use the existing lab SSH key material and host known_hosts files already
configured for this workspace. The agent may reboot the Linux lab OS and
reconnect when that OS is the running system.

## Next experiments (pick one; do not combine)

1. Reinstall to a current Fedora (or Debian + newer kernel); repeat
   `intel-first-repro.md`.
2. Suspend/resume with Intel panel ownership + discrete `OFF`.
3. Native GT 750M outputs (separate from DisplayLink).
4. Storage flush-pattern follow-up only with an explicit checkpoint.

Default when unsure: leave APFS alone; read `intel-first-repro.md` before
changing NVRAM or the bootloader.
