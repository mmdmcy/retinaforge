# Hyprland on this MacBookPro11,3

The first Hyprland session was **only a DRM proof**: three binds
(`SUPER+Return`, `SUPER+Q`, `SUPER+M` to exit) so we could see whether
Aquamarine would paint `eDP-2`. It was not a desktop.

Verified **2026-08-17**: a real Hyprland 0.56 session on the Intel lid
(`Desktop=Hyprland`, `Type=wayland`, eDP-2 2880×1800, Command = Super).
Plasma Wayland remains the `recreate-desktop.sh wayland` default because
that matches the existing KDE install. Hyprland is the path you want
for Omarchy.

Lab note: [`docs/source-notes/2026-08-17-hyprland.md`](../source-notes/2026-08-17-hyprland.md).
Omarchy install: [`omarchy.md`](omarchy.md).

## This CachyOS boot (keep the Intel UKI)

```bash
sudo pacman -S --needed waybar wofi grim slurp wl-clipboard brightnessctl \
  xdg-desktop-portal-hyprland mako
sudo ./scripts/graphics/recreate-desktop.sh hyprland
```

Back to Plasma Wayland:

```bash
sudo ./scripts/graphics/recreate-desktop.sh wayland
```

Command (⌘) is Super. Option (⌥) is Alt. This machine had
`hid_apple swap_opt_cmd=1`, which made Command act as Alt. The installer
sets `swap_opt_cmd=0` and `fnmode=1` (brightness/volume without Fn).

| Bind | Action |
| --- | --- |
| ⌘+Space | launcher (wofi) |
| ⌘+Return | terminal |
| ⌘+Q / ⌘+W | close window |
| ⌘+1…9 | workspace |
| ⌘+Tab | next workspace |
| ⌘+F | fullscreen |
| ⌘+B | Firefox |
| ⌘+D | files |
| ⌘+Shift+3 / 4 | screenshot / region |
| ⌘+Shift+E | exit to greeter |
| 3-finger swipe | workspaces |

Configs:

- `/usr/local/share/retinaforge/hyprland-retinaforge.conf` — DRM pin,
  panel scale 2, keyboard, brightness. CachyOS hyprlang.
- `/usr/local/share/retinaforge/hyprland-retinaforge.lua` — **same pin
  for Omarchy 4** (Hyprland 0.56 Lua). **Omarchy dofiles this.**
- `/usr/local/share/retinaforge/hyprland-intel.conf` — CachyOS daily
  binds + waybar. **Do not use this on Omarchy** (it would fight the rice).

No compositor blur. Haswell Iris Pro stays cooler without it.

Wrapper: `retinaforge-hyprland-intel` runs
`Hyprland --config /usr/local/share/retinaforge/hyprland-intel.conf`.
Session file: `hyprland-intel.desktop`.

## Config overlay on 0.56 (what filled the screen)

CachyOS Hyprland is **0.56.2**. Since 0.55 the native config is Lua;
hyprlang `.conf` still loads (`Config is NOT lua, loading regular mgr`)
but several old keys are gone. The red on-screen overlay was parse
errors, not a DRM failure. Hyprland had already modeset eDP-2.

Dropped keys that we shipped at first:

| Old (invalid on 0.56) | What to use |
| --- | --- |
| `input:touchpad:tap` | `tap-to-click` (hyprlang) / `tap_to_click` (Lua) |
| `misc:vfr` | omit (VFR lives under `debug` now; leave it) |
| `dwindle:pseudotile` | omit (`preserve_split` stays) |

The daily file `source`s the hardware file, so each hardware error
showed twice plus the dwindle line.

After those three were gone:

```bash
Hyprland --verify-config --config /usr/local/share/retinaforge/hyprland-intel.conf
# => config ok
hyprctl reload
```

Run verify as the **seated user**. As root, with a session already on
the GPU, `--verify-config` has aborted (SIGABRT) on this box.

`hyprctl reload` clears the overlay once the file parses. If a stale
overlay is stuck, ⌘+Shift+E and log into **hyprland-intel** again.

## Command vs Option

| `swap_opt_cmd` | ⌘ Command | ⌥ Option |
| --- | --- | --- |
| `0` (what we want) | Super | Alt |
| `1` (what this box had) | Alt | Super |

Live: `/sys/module/hid_apple/parameters/swap_opt_cmd`. Persistent:
`/etc/modprobe.d/retinaforge-hid-apple.conf`.

Do not set xkb `applealu_iso` + `mac` on top of that hid map.

## If you install Omarchy

Omarchy 4 configs are **Lua** (`~/.config/hypr/hyprland.lua`). A
`source = …hyprland-retinaforge.conf` line does nothing there.

Full order, hard stops, kernel/`force_igd`, LUKS2+btrfs, keep macOS:
[`omarchy.md`](omarchy.md).

Short version after the Omarchy root exists and the Intel UKI lights
the lid:

```bash
sudo ./scripts/graphics/recreate-desktop.sh omarchy
```

Then last line of `~/.config/hypr/hyprland.lua`:

```lua
dofile("/usr/local/share/retinaforge/hyprland-retinaforge.lua")
```

You do **not** need Debian for Hyprland. You also do not need to wipe
CachyOS to “get Omarchy’s desktop”: Hyprland on this Intel UKI is the
same compositor. Omarchy is extra rice + their package set, on top of
the same lid recipe.
