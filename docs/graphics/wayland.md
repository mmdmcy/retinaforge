# Wayland on this MacBookPro11,3 (Intel lid)

Verified **2026-08-17**: Plasma Wayland (`plasma.desktop`) on Iris Pro,
SDDM `DisplayServer=wayland`, framebuffer `i915drmfb`, eDP-2 2880×1800.
KWin uses **legacy modeset** (`KWIN_DRM_NO_AMS=1`). Atomic pageflips
timed out on this Haswell eDP; do **not** “fix” that by turning
`i915.enable_dc` back on.

Hyprland is a real session now (Command = Super), not the three-bind
DRM probe. Overlay / 0.56 keys: [`hyprland.md`](hyprland.md). Omarchy:
[`omarchy.md`](omarchy.md). Plasma Wayland remains the default
`recreate-desktop.sh wayland` target.

```bash
sudo ./scripts/graphics/enable-wayland-intel.sh
sudo ./scripts/graphics/check-wayland-intel.sh
sudo ./scripts/graphics/disable-wayland-intel.sh   # Plasma X11 again
```

Full ordered install (UKI + lid + power + Wayland):
[`recreate.md`](recreate.md).

Native HDMI/TB still sit on the GT 750M.

## Recreate (any distro with SDDM + Plasma)

Needs the Intel lid path already (`check-intel-first-panel.sh` green).

1. `install-wayland-intel.sh` — udev `/dev/dri/intel-igpu` → PCI `00:02.0`,
   `environment.d` DRM pins, Plasma env `KWIN_DRM_NO_AMS=1`.
2. `enable-wayland-intel.sh`:
   - Stash `/etc/sddm.conf.d/10-x11.conf`, `10-intel.conf`, and **every**
     `*.bak*` **out of** that directory (not a rename in place).
   - Write `/etc/sddm.conf` last (`DisplayServer=wayland`, Autologin
     session from `wayland-sessions`, `RememberLastSession=false`).
   - `systemctl --user unmask plasma-kwin_wayland.service`
   - Stop the previous graphical session (`sddm-free-vt.sh`) so VT 1 is
     free, `reset-failed`, then `start` SDDM (not a crash-loop restart).
3. Tries Plasma Wayland, then Weston, then Hyprland. Restores X11 only
   if nothing stays up.

Plasma 5 Debian may name the session `plasmawayland.desktop`; Plasma 6
uses `plasma.desktop` in `wayland-sessions`. The enable script picks
whichever exists. Autologin user comes from SDDM `User=`, else
`SUDO_USER`, else the first uid ≥ 1000. Do not hardcode a login name.

GDM/GNOME is a different recipe. This one is **SDDM + Plasma**.

## Traps that looked like “Wayland cannot modeset”

| Symptom | Actual cause |
| --- | --- |
| Autologin starts `plasmax11` even when Session= is a Wayland desktop | SDDM 0.21 loads **all** files in `sddm.conf.d` (not only `*.conf`). `autologin.conf.bak-*` overrode Session. `/etc/sddm.conf` is the last file and must carry Autologin + `DisplayServer=wayland`. |
| Greeter `HELPER_TTY_ERROR`, sddm `start-limit-hit` | Previous Plasma X11 still owned VT 1. `systemctl restart sddm` does not always reap it. Stop SDDM, kill `startplasma-x11` / `kwin_*` / `Xorg`, `reset-failed`, wait, `start`. |
| `Unit plasma-kwin_wayland.service is masked` | X11 bring-up masked the user unit (`~/.config/systemd/user/plasma-kwin_wayland.service` → `/dev/null`). `startplasma-wayland` exits in ~1s. Unmask before Autologin. |
| `kwin_wayland_drm: Pageflip timed out` | Atomic modeset on this eDP. `KWIN_DRM_NO_AMS=1`. Not an `enable_dc` bug. |
| SSH-root `kwin_wayland` segfault / Weston `could not open seat` | No seat. Invalid test. SDDM autologin (or a seated greeter) is the harness. |
| Hyprland ignores `by-path` DRM nodes | Aquamarine cannot parse colons in the path. Use `/dev/dri/intel-igpu`. |
| Compositor on nouveau `card0` / `renderD128` | 750M Off or wrong `KWIN_DRM_DEVICES`. Pin Iris Pro. |

## Environment (installed)

`/etc/environment.d/99-intel-drm.conf` and `/etc/xdg/plasma-workspace/env/retinaforge-intel-drm.sh`:

- `KWIN_DRM_DEVICES=/dev/dri/intel-igpu`
- `KWIN_DRM_NO_AMS=1`
- `KWIN_DRM_USE_MODIFIERS=0`
- `KWIN_DRM_DISABLE_TRIPLE_BUFFERING=1`
- `AQ_DRM_DEVICES` / `AQ_NO_ATOMIC=1` (Hyprland fallback)
- `WLR_DRM_DEVICES` / `WLR_DRM_NO_ATOMIC=1`

## Debian packages

`sddm`, `plasma-workspace`, `kwin-wayland`, `weston` (fallback). Then the
same `enable-wayland-intel.sh`. Session file may be
`plasmawayland.desktop`.
