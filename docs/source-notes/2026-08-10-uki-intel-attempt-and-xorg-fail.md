# UKI Intel Path, nvidia-off, force_igd Breakthrough (2026-08-10)

## Abstract

Full-day Intel-first lab session on `MacBookPro11,3` + CachyOS. Built an
in-tree **Intel daily** stack (UKI rebuild with nvidia-off, Limine autoboot,
verify scripts, Xorg Intel config). macOS `gpu-policy %01` + cold shutdown
still yields `%00` on Linux power-on, but adding **`apple_gmux.force_igd=1`**
on the UKI path produced a **major mux breakthrough**: GMUX switches to IGD,
i915 eDP-1 is **connected**, Apple EDID is readable at 2880×1800, and the
ghost-panel `failed to retrieve link info` line is **gone**. Remaining
blocker: kernel DRM reports **0 modes** on eDP-1; Xorg fails
`failed to set mode` → black panel with backlight on (1023/1023).

## Part 1 — Morning: UKI + macOS NVRAM (ghost panel, NVIDIA hybrid)

See initial procedure in git history. Summary:

| Check | Result |
| --- | --- |
| UKI / StubInfo | Present |
| `i915` enumerated | Yes |
| nvidia/nouveau (before rebuild) | Often loaded on hybrid path |
| i915 eDP | `failed to retrieve link info, disabling eDP` |
| Panel / Xorg | NVIDIA `DFP-3` or Intel Xorg-only → no screens |
| `gpu-policy` after Linux boot | `%00` despite macOS `%01` before cold off |

## Part 2 — Infrastructure built in-tree

### Scripts (under `scripts/graphics/`)

| Script | Role |
| --- | --- |
| `enable-intel-daily.sh` | nvidia-off modprobe, Intel Xorg, Limine UKI default, disable `mbp-cool-idle`, early gpu-policy logger |
| `disable-nvidia-off.sh` | Emergency SSH recovery only (re-enable NVIDIA for LTS) |
| `build-apple-set-os-uki.sh` | Rebuild UKI with `mkinitcpio-intel-uki.conf` |
| `limine-set-default-uki.sh` | Flat top-level UKI entry; `default_entry: 1` (1-based); 5s autoboot |
| `limine-restore-discrete-default.sh` | Emergency LTS menu default |
| `verify-intel-uki-boot.sh` | StubInfo, modules, eDP owner, gpu-policy |
| `nvidia-off-modprobe.conf` | blacklist + `install … /bin/false` |
| `apple-gmux-intel.conf` | `options apple_gmux force_igd=1` |
| `mkinitcpio-intel-uki.conf` | `MODULES=(apple-gmux i915)` + modprobe FILES |
| `xorg-intel-panel.conf` | modesetting on card1, 2880×1800, `AutoAddGPU false` |
| `retinaforge-log-gpu-policy.sh` | Early-boot efivar logging |
| `prepare-intel-boot.sh` | Linux-side prep (legacy; prefer enable-intel-daily) |

### macOS (`macos/scripts/`)

| Script | Role |
| --- | --- |
| `prepare-intel-from-macos.sh` | `gpu-policy %01` + `gpu-power-prefs` Intel |
| `set-gpu-policy-intel.sh` | `nvram gpu-policy=%01` |

### Boot / service fixes

1. **Limine autoboot** — UKI must be a **flat leaf entry**, not `/+Folder` +
   `//child`. `default_entry: 0` is invalid on Limine v12 (1-based). Submenu
   entries skip the countdown.
2. **`retinaforge-nouveau.service`** — conflicted with nvidia-off (`install
   nouveau /bin/false`). Removed during intel-daily; do not re-enable on
   nvidia-off path.
3. **`mbp-cool-idle.service`** — lab unit (“MacBook cool idle, dGPU off, lid
   backlight”). Runs **after** i915 probe (~14s); not the cause of the ~6s
   eDP failure. Disabled during Intel experiments as a controlled variable.

### Agent policy (docs)

Intel i915 desktop is the **primary goal**. Discrete/LTS NVIDIA is **emergency
SSH recovery only** — documented in `docs/session-handoff.md` and
`docs/fleet-naming.md`.

## Part 3 — Afternoon: `apple_gmux.force_igd=1` breakthrough

### Recipe (current best)

1. macOS: `gpu-policy=%01` + `gpu-power-prefs` Intel (`prepare-intel-from-macos.sh`)
2. `sudo shutdown -h now` (cold off; remote SSH OK)
3. Power on → Limine autoboot **RetinaForge Intel UKI** (~5s)
4. UKI cmdline includes: `apple_gmux.force_igd=1`
5. Initramfs: `MODULES=(apple-gmux i915)` so GMUX switches **before** i915 probe

### Kernel log (success shape)

```text
apple_gmux: Found gmux version 4.0.8 [indexed]
apple_gmux: Switching to IGD
i915: Found haswell (device ID 0d26) ...
```

**No** `failed to retrieve link info, disabling eDP` on the best boots.

### DRM / Xorg state (partial)

| Check | Without force_igd | With force_igd |
| --- | --- | --- |
| i915 eDP link-info fail | Yes | **No** |
| `card*-eDP-*` status | disconnected / ghost | **connected** |
| EDID (Xorg DDC) | phantom or wrong mode | **2880×1800 Apple** |
| Kernel modes on eDP-1 | 0 | **0** (still) |
| `modetest` modes count | 0 | **0** |
| Xorg set mode | no screens / wrong res | **`failed to set mode`** |
| Panel | logs or black | **black, backlight max** |
| `fb0` | `simpledrmdrmfb` | `simpledrmdrmfb` (not `i915drmfb` yet) |

### gpu-policy timing

`retinaforge-log-gpu-policy` at early boot: `gpu-policy` data already `%00`
even when macOS had `%01` immediately before cold shutdown. Confirms firmware
or early boot still presents discrete policy to Linux; **`force_igd` bypasses
this for GMUX switch** but does not yet complete DRM mode enumeration.

### Wrong turns (documented)

| Attempt | Outcome |
| --- | --- |
| `apple_gmux.force_idg=1` (typo) | Unknown parameter, ignored |
| UKI rebuild set `default_entry: 3` | Landed on bare `linux-cachyos`, no StubInfo |
| Xorg without Monitor section | Picked 2560×1600 initial mode |
| Remote macOS bless Limine | `0xe00002e2` — use Limine autoboot or manual EFI |

## Comparison to 2026-08-01 success

| Factor | 2026-08-01 | 2026-08-10 end state |
| --- | --- | --- |
| UKI / apple_set_os | Yes | Yes |
| macOS Intel NVRAM | Yes | Yes (`gpu-policy %01`) |
| nvidia-off in UKI | Not recorded | Yes |
| `apple_gmux.force_igd` | **Not in notes** | **Yes — new variable** |
| Primary fb | `i915drmfb` | `simpledrmdrmfb` |
| Kernel eDP modes | Present | **0** |
| Desktop | Working Intel | Black (backlight on) |

**Hypothesis.** The 08-01 success may have relied on implicit GMUX IGD switch
(firmware + prefs) without `force_igd`, or on a firmware state we have not
re-captured. `force_igd` is necessary but not sufficient on today's firmware.

## Next experiments (one factor each)

1. **Cold macOS prep + force_igd UKI every boot** — confirm whether `%01` +
   `force_igd` together populate kernel DRM modes (not yet tested as a strict
   paired cold cycle after UKI rebuild).
2. **i915 display power / PC8** — recurring `hsw_enable_pc8` warnings during
   probe; try `i915.enable_dc=0` or runtime PM tweaks on UKI cmdline.
3. **Delayed i915 reload** after GMUX switch (risky; SSH recovery ready).
4. **Diff UKI / kernel vs 08-01 backup** — `cachyos-apple-set-os.efi.bak-*`
   on ESP.
5. **Do not** re-enable `retinaforge-nouveau.service` or `mbp-cool-idle` on
   intel-daily without documenting why.

## Operator recovery

- SSH up, black panel: expected on current force_igd builds; verify with
  `verify-intel-uki-boot.sh` and `modetest -M i915 -c`.
- Emergency desktop: `disable-nvidia-off.sh` → Limine `linux-cachyos-lts`.
- macOS NVRAM: `prepare-intel-from-macos.sh` → cold off.

## Measurements (force_igd black-panel session)

| Metric | Value |
| --- | --- |
| Backlight | 1023/1023 |
| UKI kernel | `7.1.5-1-cachyos` |
| nvidia/nouveau | absent |
| gmux switch log | `Switching to IGD` |
