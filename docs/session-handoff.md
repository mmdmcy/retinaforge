# Next Session Handoff

Last updated: 2026-08-01 (Intel panel path validated; graphics note published)

Private operational checklist for agents. Public science lives in
`docs/findings.md` and `docs/source-notes/2026-08-01-intel-panel-and-display-path.md`.
Do not copy hostnames, addresses, keys, or conversation text into publishable
files.

## Machine layout

| Part | Role |
| --- | --- |
| sda1 | Apple EFI |
| sda2 | Big Sur APFS (preserve) |
| sda3 | Linux ESP / Limine `/boot` |
| sda4 | CachyOS ext4 root |

Big Sur and CachyOS both remain bootable. Re-inventory before repartitioning.

## Graphics (verified 2026-08-01)

1. macOS: `gpu-power-prefs` Intel `%01%00%00%00` (do not rely on Linux writes).
2. Limine **default_entry** = UKI / EFI-stub **CachyOS Intel probe** (not bare
   `protocol: linux`).
3. Expect `i915drmfb`, eDP 2880×1800, switcheroo IGD selected.
4. After boot, confirm DIS `OFF` via switcheroo if thermals matter; DIS may
   return to `Pwr` across sessions.
5. Never live-force IGD / careless mux handoff (black screen history).

Research write-up:
[`source-notes/2026-08-01-intel-panel-and-display-path.md`](source-notes/2026-08-01-intel-panel-and-display-path.md).

## Linux lab desktop notes

- Prefer **Xfce/X11** over Plasma for stability on this multi-GPU setup.
- Set DRM device preference to the Intel card when both GPUs enumerate.
- DisplayLink: masked/off by default; on-demand helpers
  `present-on` / `present-layout` / `present-off` (USB dock path; dGPU not
  required). Dual DisplayLink is hot — presenting only.
- Lid/suspend ignore + masked sleep targets were configured for long SSH lab
  sessions; lid-closed cooling is still poor — avoid heavy load.

## Hard stops (unchanged)

- Writable MSI + NCQ: never for samples.
- No casual USB reprovision, repartition, or physical write tests without a
  fresh user-present checkpoint.
- Do not mix storage and NVIDIA/GMUX changes in one patch or one experiment.

## Access (private)

- Same LAN host for macOS and Linux (whichever is booted).
- macOS SSH: `known_hosts_macos_mbp` + existing ed25519 key.
- Linux SSH: `known_hosts_cachyos` + same key family; sudo configured for
  unattended lab commands on the Linux user.
- Agent may reboot the Linux lab OS and reconnect when that OS is the running
  system.

## Next useful experiments (pick one; do not combine)

1. Suspend/resume with Intel panel ownership + DIS `OFF`; record failures.
2. Native GT 750M outputs (Nouveau or documented proprietary) — separate from
   DisplayLink.
3. Measure whether switcheroo `OFF` equals GMUX rail-off (instrumented).
4. Storage: only if explicitly reopened — ext4-on-dm-crypt flush isolation.

Default when unsure: leave APFS alone, boot Big Sur, read the 2026-08-01
graphics note before changing NVRAM or Limine.
