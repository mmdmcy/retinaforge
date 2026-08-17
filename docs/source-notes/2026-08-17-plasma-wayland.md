# Plasma Wayland on Iris Pro (2026-08-17)

## Abstract

With the Intel lid already at `i915drmfb` 2880×1800, Plasma Wayland is a
working daily session on this `MacBookPro11,3` if KWin is pinned to
`/dev/dri/intel-igpu` and forced to **legacy modeset**
(`KWIN_DRM_NO_AMS=1`). Atomic DRM pageflips timed out on this Haswell
eDP; that is not fixed by turning `i915.enable_dc` back on.

Hyprland and Weston also start on the same DRM pin. The same evening,
Hyprland 0.56 became a real seated session (Command as Super);
[`2026-08-17-hyprland.md`](2026-08-17-hyprland.md). The session that
matches the existing Plasma desktop is still `plasma.desktop` /
`startplasma-wayland`.

## What blocked it (all required)

1. **SDDM still X11.** `/etc/sddm.conf.d/10-x11.conf` overrode CachyOS
   `zz-wayland.conf`. Autologin `Session=` of a Wayland desktop is
   ignored while `DisplayServer=x11` (SDDM looks in `xsessions` and
   falls back to last X11 session).
2. **SDDM 0.21 reads every file in `sddm.conf.d`**, not only `*.conf`.
   `autologin.conf.bak-*` sat after `autologin.conf` and forced
   `Session=plasmax11.desktop` again. `/etc/sddm.conf` is loaded last
   and must carry Autologin + `DisplayServer=wayland`. Stash bak files
   **out of** that directory.
3. **`RememberLastSession` + `state.conf`** pointed at
   `/usr/share/xsessions/plasmax11.desktop`.
4. **VT 1 busy.** `systemctl restart sddm` left `startplasma-x11`
   running. Wayland greeter then died `HELPER_TTY_ERROR` and systemd
   hit `start-limit-hit`. Stop SDDM, kill the old graphical helpers,
   `reset-failed`, wait, `start`.
5. **`plasma-kwin_wayland.service` masked** in the user systemd dir
   (X11 bring-up, `~/.config/systemd/user/…` → `/dev/null`).
   `startplasma-wayland` logged `UnitMasked` and exited in about a
   second (`Can't open display` / xmessage). Unmask, then Autologin.
6. **Invalid harness.** SSH-root `kwin_wayland` segfaulted (no
   `XDG_RUNTIME_DIR` / seat). Weston `libseat: could not open seat`.
   Seated SDDM autologin is the test.

KWin greeter with `KWIN_DRM_NO_AMS=1` did `Connect` once VT 1 was free.
Plasma then started: `startplasma-wayland`, `kwin_wayland`,
`plasmashell`, eDP-2 enabled, no pageflip timeout in journal.

## Not the fix

- Re-enabling `i915.enable_dc`
- Live mux hops (`IGD` / `DIS`)
- Hyprland as the required desktop (it proved the DRM pin; Plasma is
  the session)

## Recreate

[`docs/graphics/recreate.md`](../graphics/recreate.md),
[`docs/graphics/wayland.md`](../graphics/wayland.md).

```bash
sudo ./scripts/graphics/enable-wayland-intel.sh
sudo ./scripts/graphics/check-wayland-intel.sh
```
