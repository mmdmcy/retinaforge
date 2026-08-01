# Next Session Handoff

Last updated: 2026-08-01 (session wrap: Linux-first lab; repro docs ready)

Private operational checklist for agents. Public science and reproduction:
- `docs/graphics/intel-first-repro.md`
- `docs/source-notes/2026-08-01-intel-panel-and-display-path.md`
- `docs/findings.md` (graphics subsection)

Do not copy hostnames, addresses, keys, or conversation text into publishable
files.

## User intent (end of 2026-08-01 session)

- **Linux-first** on this `MacBookPro11,3` (lab / primary experiment machine).
- Big Sur kept as recovery/reference, not the daily workaround path.
- Considering leaving **CachyOS** for something stabler (**Fedora preferred**
  over Debian stable for newer kernel / Apple Set OS comfort). Not done yet.
- Optional later: shrink APFS, grow Linux — only with explicit user-present
  checkpoint + backup. Not started.
- Work laptop may be ThinkPad T560 or another Mac; this MBP is the Apple/NVIDIA
  (+ AHCI) lab box.

## Machine layout (re-inventory before changes)

| Part | Role |
| --- | --- |
| sda1 | Apple EFI |
| sda2 | Big Sur APFS (preserve) |
| sda3 | Linux ESP / Limine `/boot` |
| sda4 | CachyOS ext4 root |

## Graphics — restore after any Linux reinstall

Follow **`docs/graphics/intel-first-repro.md`** end-to-end:

1. macOS: `macos/scripts/set-gpu-power-prefs-intel.sh` → `%01%00%00%00`
2. Boot via **UKI / EFI-stub** entry (Limine `protocol: efi` or systemd-boot UKI).
   Bare `protocol: linux` is insufficient for Apple Set OS on this machine.
3. Linux: `scripts/graphics/check-intel-first-panel.sh`
4. Optional cooler idle: `echo OFF | sudo tee /sys/kernel/debug/vgaswitcheroo/switch`
5. Never live-force GMUX / IGD mid-session.

**NVRAM now:** Intel prefs (`%01…`) for the Linux panel path.

DisplayLink (occasional only): install `displaylink`/`evdi`, then repo helpers
`scripts/graphics/present-{on,layout,off}`. Dual DisplayLink is hot.

Desktop note: **Xfce/X11** was stabler than Plasma here; prefer Intel DRM node
when both GPUs enumerate.

## Distro note for next install

| Distro | Fit |
| --- | --- |
| **Fedora (current)** | Good default: newer kernel, UKI/systemd-boot friendly |
| Debian stable | OK if you add a **newer kernel** (backports) — stock stable can lag Apple quirks |
| CachyOS (current) | Works; user prefers to migrate away for stability |

Recipe is distro-agnostic; validate with `check-intel-first-panel.sh`.

## In-repo vs machine-only

**In repo (enough to bring graphics back up):**

- `docs/graphics/intel-first-repro.md`
- `macos/scripts/set-gpu-power-prefs-intel.sh`
- `scripts/graphics/check-intel-first-panel.sh`
- `scripts/graphics/present-on` / `present-layout` / `present-off`

**Was configured on the live CachyOS install (recreate if wiped):**

- SSH + sudo for lab user, Wi-Fi, keymap
- Always-on / lid-ignore / masked sleep (optional)
- SDDM/Xfce autologin, scale factors
- DisplayLink packages masked by default

## Hard stops

- Writable MSI + NCQ: never.
- No casual USB reprovision, repartition, or physical write tests without a
  fresh user-present checkpoint.
- Do not mix storage and NVIDIA/GMUX changes in one patch or experiment.

## Access (private)

- Same LAN host for macOS and Linux (whichever is booted).
- macOS: `known_hosts_macos_mbp` + existing ed25519 key.
- Linux: `known_hosts_cachyos` + same key family; sudo configured for lab user.
- Agent may reboot the Linux lab OS and reconnect when that OS is running.

## Next experiments (pick one; do not combine)

1. Reinstall to Fedora (or Debian+new kernel); repeat intel-first-repro.
2. Suspend/resume with Intel panel + DIS `OFF`.
3. Native GT 750M outputs (separate from DisplayLink).
4. Optional APFS shrink / Linux grow — only if user explicitly starts that
   checkpoint.

Default when unsure: leave APFS alone; read `intel-first-repro.md` before
touching NVRAM or the bootloader.
