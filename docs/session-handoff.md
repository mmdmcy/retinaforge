# Next Session Handoff

Last updated: 2026-08-17 — **Hyprland 0.56 on the Intel lid; Omarchy is a port**

## Session wrap (2026-08-17, night)

Plasma Wayland (morning) and Hyprland 0.56 (evening) both sit on the
Intel UKI lid. Hyprland overlay was three removed hyprlang keys
(`tap`, `vfr`, `pseudotile`); `verify-config` → `config ok` after
reload. Command = Super (`swap_opt_cmd=0`).

**Omarchy next:** do not stock-ISO wipe the internal SSD. Skip LUKS.
Keep macOS. Stock Arch kernels likely lack `force_igd`. After an
Omarchy root exists: `recreate-desktop.sh omarchy`, then last line of
`~/.config/hypr/hyprland.lua`:
`dofile("/usr/local/share/retinaforge/hyprland-retinaforge.lua")`.
Do not `source` the `.conf`. Do not run `enable-wayland-intel.sh` on
Omarchy (SDDM). Cook-book: `docs/graphics/omarchy.md`.

MacBook is shut down; do not claim a live check until the next boot.

Public docs: `docs/graphics/hyprland.md`, `docs/graphics/omarchy.md`,
`docs/source-notes/2026-08-17-hyprland.md`,
`docs/source-notes/2026-08-17-plasma-wayland.md`.

## Session wrap (2026-08-16, evening)

Intel-first desktop is **repeatable** on this machine. `check-intel-first-panel.sh`
and `verify-intel-uki-boot.sh` both passed after a UKI reboot.

**Cause of the old 0-modes gap:** Haswell `DDI_BUF_CTL_A` lacked `DDI_A_4_LANES`.
Firmware boots Linux on DIS, so Intel GOP never sets the bit. i915 then treats
PORT_A as 2-lane; 2880×1800 is `CLOCK_HIGH`. Full record:
`docs/source-notes/2026-08-16-hsw-ddi-a-4-lanes.md`.

**Left on disk (Linux, last confirmed 2026-08-16):**

- Limine **default_entry = 2** = `RetinaForge Intel UKI`
  (`cachyos-apple-set-os.efi`, kernel `7.1.5-1-cachyos`, cmdline
  `apple_gmux.force_igd=1 i915.enable_dc=0 modprobe.blacklist=i915`).
- Recovery: `RetinaForge NVIDIA LTS` remains **entry 1** (do not delete).
  `disable-nvidia-off.sh` before that boot if nvidia-off is on the rootfs.
- `retinaforge-i915-ddi-4lanes.service` enabled; pokes MMIO then loads i915
  **before** SDDM. Guarded by `apple_gmux.force_igd=1` on the cmdline.
- Intel Xorg: `/etc/X11/xorg.conf.d/40-intel-panel.conf` + `50-disable-nvidia.conf`.
- eDP-handoff profile still **opt-in only** (wedges SSH). Historical 08-01 UKI
  and video-modes UKI stay as manual entries; do not make them default.
- Do **not** run `limine-set-default-uki.sh` / `enable-intel-daily.sh`'s old
  Limine rewrite — it strips extra Intel entries and forces UKI to entry 1.

**Do not** repeat historical UKI + NVRAM. **Do not** copy Big Sur AGS
(`docs/graphics/why-not-macos-ags.md`).

| Doc | Contents |
| --- | --- |
| `docs/source-notes/2026-08-16-hsw-ddi-a-4-lanes.md` | DDI A 4-lane root cause + persistent recipe |
| `docs/source-notes/2026-08-16-dri-prime-nouveau.md` | OpenGL offload to nouveau while Intel owns the lid |
| `docs/graphics/intel-first-repro.md` | **Cook-book to reproduce** (start here after a wipe scare) |
| `docs/source-notes/2026-08-10-uki-intel-attempt-and-xorg-fail.md` | `force_igd` breakthrough, 0 DRM modes (now explained) |
| `docs/source-notes/2026-08-10-edp-handoff-research.md` | DIS-first handoff v1–v3, `NEEDS_EDP_CONFIG`, boot wedge |
| `docs/source-notes/2026-08-13-historical-uki-retest.md` | 08-01 UKI + verified NVRAM still ghost-panel |
| `docs/graphics/why-not-macos-ags.md` | Why Linux cannot copy Big Sur AGS on this GMUX |
| `scripts/graphics/enable-intel-daily.sh` | Intel path: force_igd, DDI poke, Xorg; handoff off |
| `scripts/graphics/retinaforge-i915-ddi-4lanes.py` | MMIO poke + i915 load |
| `scripts/graphics/enable-intel-edp-handoff.sh` | Opt-in handoff profile only |

**Resume:** Intel panel is the daily UKI default. Plasma Wayland and
Hyprland 0.56 both work on that lid. OpenGL `DRI_PRIME=1` works with
nouveau; that is not AGS. Omarchy is a **port** (`docs/graphics/omarchy.md`)
— never the stock ISO as a dedicated-drive wipe of the internal SSD.
Keep NVIDIA LTS as fallback. Reproduce from
`docs/graphics/recreate.md` / `docs/graphics/intel-first-repro.md`,
not from chat memory.

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

**UKI / Intel daily path (2026-08-16, working):**

- In-tree stack: `enable-intel-daily.sh`, `build-apple-set-os-uki.sh`
  (`SKIP_LIMINE=1`), `verify-intel-uki-boot.sh`,
  `retinaforge-i915-ddi-4lanes.py`.
- Mux: `apple_gmux.force_igd=1` → `IGD:+:Pwr`, eDP connected.
- Modes: poke `DDI_A_4_LANES` then load i915 → `i915drmfb`, 2880×1800, 4 lanes.
- Desktop: Xorg modesetting + glamor on Iris Pro, Plasma X11 via SDDM.
- macOS `gpu-policy` may still read `%00` on Linux; `force_igd` is sufficient
  for the mux. Full record:
  `docs/source-notes/2026-08-16-hsw-ddi-a-4-lanes.md`.
- Do **not** re-enable `retinaforge-nouveau.service` on nvidia-off path.
- Do **not** re-enable eDP-handoff as default.

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

## Graphics — current state (2026-08-16)

**Intel panel path is working.** `i915drmfb`, eDP 2880×1800, 4 lanes, Plasma
X11 on Iris Pro. Recipe: UKI `force_igd` + delayed i915 + DDI A 4-lane poke.
See `docs/graphics/intel-first-repro.md` and
`docs/source-notes/2026-08-16-hsw-ddi-a-4-lanes.md`.

The 2026-08-01 `i915drmfb` boot remains historically interesting (firmware
probably left mux on IGD so GOP had already set `DDI_A_4_LANES`) but is **not**
the reproduction path. 08-05 / 08-13 negatives are explained by DIS-first GOP
leaving PORT_A at 2 lanes (or ghost-panel when i915 probed on DIS).

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

Do **not** burn another session on identical NVRAM + cold UKI loops. Mux
investigation closed 2026-08-08: Linux UKI boots land on DIS regardless of
NVRAM. `force_igd` is the mux fix; DDI A 4 lanes is the modes fix.

Optional after Intel owns the panel: switcheroo `OFF` for DIS. Never
live-force GMUX mid-session. Do not re-enable eDP-handoff as default.

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
- Boot-time `apple_gmux.force_igd=1` plus the DDI A 4-lane poke are the Intel
  daily path. Do not stack eDP-handoff or storage experiments on the same boot.

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

0. ~~Intel daily desktop~~ — **DONE 2026-08-16** (`force_igd` + DDI A 4-lane
   poke; check scripts pass). Keep NVIDIA LTS as Limine entry 1 for recovery.
0b. **Do not** run `limine-set-default-uki.sh` unless you intend to flatten
    the menu (it strips extra Intel UKI entries).
1. ~~UKI nvidia-off rebuild~~ — **DONE 2026-08-10** (`build-apple-set-os-uki.sh`).
2. ~~In-tree verify script~~ — **DONE** (`verify-intel-uki-boot.sh`).
3. ~~DRM modes on eDP~~ — **DONE 2026-08-16** (DDI A 4 lanes).
4. ~~E2 — clean-slate retry~~ — **RUN 2026-08-07, negative** (see 08-07 note).
5. ~~Pin / retest the 08-01 UKI~~ — **RUN 2026-08-13, negative** (see 08-13 note).
6. Suspend/resume **on the Intel UKI desktop** (now in scope).
7. Optional: switcheroo `OFF` for DIS after IGD owns the panel (cooler idle).
   Do not combine with eDP-handoff v3. **Conflicts with DRI_PRIME** (needs DIS
   powered + nouveau).
8. Kernel DMI quirk: `patches/0003-i915-mbp11-3-ddi-a-4-lanes.patch` (unbuilt).
9. Native GT 750M outputs (separate from DisplayLink).
10. Storage flush-pattern follow-up only with an explicit checkpoint.
11. ~~Indexed eDP handoff as default boot~~ — **tried 2026-08-10, do not
    re-enable on default** (SSH wedge). Opt-in profile only.
12. ~~DRI_PRIME OpenGL offload~~ — **DONE 2026-08-16** (`DRI_PRIME=1` → nouveau
    NVE7, Intel keeps the lid). Vulkan stays Intel. Not AGS.
    `docs/source-notes/2026-08-16-dri-prime-nouveau.md`.

Default when unsure: leave APFS alone; read the 2026-08-06 investigation note
before changing NVRAM or the bootloader.
