# RetinaForge plate (MacBookPro11,3)

A small Plasma/X11 tray plate for the Late-2013 15-inch Retina MacBook Pro
that this repository actually tests. Left-click the jewel in the taskbar to
open it.

It shows whether the lid is on Intel (`i915drmfb`), whether the unused
GT 750M is powered, package and dGPU temperature, and fan RPM. The two
buttons only write vgaswitcheroo `OFF` / `ON` — sleep or wake the 750M
while Iris Pro keeps the panel. They **do not** send `IGD` or `DIS`.
Those mux hops black the lid on this indexed Apple GMUX.

This is not Big Sur Automatic Graphics Switching. **Run on 750M** on the
plate wakes the chip if needed and starts the command with `DRI_PRIME=1`.
You do not have to memorize `prime-run`.

## Install (CachyOS / Arch, this machine)

From a clone of this repo on the laptop:

```bash
sudo pacman -S --needed python-pyqt6 ttf-ibm-plex polkit
sudo ./apps/mbp-panel/install.sh
```

Then log out and back in, or start it once:

```bash
retinaforge-mbp-panel &
```

From SSH into an already-running Plasma session:

```bash
sudo /usr/local/sbin/retinaforge-mbp-panel-start-on-seat
```

The desktop file is also copied to `/etc/xdg/autostart/` so the jewel
returns after login.

The **?** on the plate is the field card: what this toggle is for (unused
750M power only), when sage/idle is correct, **Run on 750M** vs Proton on
Intel, and what belongs on the NVIDIA LTS boot instead. The long form is
[`docs/graphics/max-value-and-omarchy.md`](../../docs/graphics/max-value-and-omarchy.md).

`install.sh` refuses to guess a Qt binding. Polkit lets a local active
`wheel` or `sudo` session run the helper without a password prompt. The
helper still has to run as root because vgaswitcheroo lives in debugfs.

## What the jewel means

| Color | Meaning |
| --- | --- |
| Sage | Lid on i915, 750M asleep (cooler idle) |
| Amber | Lid on i915, 750M powered (`prime-run` can work) |
| Red | Helper failed, or the framebuffer is not `i915` |

## Hard stops

- No panel mux hops from this app.
- No proprietary NVIDIA 470 bind/unbind.
- Writes are refused unless DMI product is `MacBookPro11,3`.
- Sleeping the 750M breaks `prime-run` until you wake it again (Run on 750M wakes it for you).

## Layout

| Path | Role |
| --- | --- |
| `retinaforge-mbp-helper.py` | Root helper: `status`, `dis-off`, `dis-on` |
| `retinaforge-mbp-panel.py` | Qt6 tray + plate |
| `org.retinaforge.mbp.policy` / `.rules` | pkexec + local wheel/sudo |
| `install.sh` | Install under `/usr/local` |
| `start-on-seat.sh` | Start inside an already-running Plasma session (SSH) |

License: GPL-2.0, same as the Linux workbench material at the repository
root.
