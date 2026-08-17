# Desk power — MacBookPro11,3

This laptop is a **desk workstation** (not used on a commute). Same
scripts on CachyOS and Debian. They do **not** touch AHCI/MSI, do
**not** re-enable `i915` display C-states, and do **not** send
`IGD`/`DIS`.

Install:

```bash
sudo ./scripts/graphics/install-work-power.sh
```

Optional on Debian: `apt install power-profiles-daemon`. Do **not**
install TLP next to it.

Config: `/etc/retinaforge/power-policy.conf`

```
COMMUTE_SLEEP=0
```

`0` is the default: never auto-sleep the GT 750M. Set `1` only if you
later want battery lid-only to park the chip.

## Default boot

Linux leaves the GT 750M **powered** (`DIS: :Pwr`). Native HDMI /
Thunderbolt on this chassis stay on that GPU even when the lid is
Intel. Keep it that way at a desk.

## What it does

| Situation | 750M | Platform profile |
| --- | --- | --- |
| AC or battery (default) | **On** (wakes if it was slept) | `balanced` |
| Extra DRM display connected | **On** | `balanced` |

Backlight: if gmux is nearly 0 on an Intel lid, raise to a dim visible
floor. Never force max on Intel (that was a black-screen recovery hack
for NVIDIA LTS).

**Sleep 750M** on the tray is manual, for lid-only at home if you want
less heat. Do not use it while you need HDMI/TB.

## What it will not do

- Auto-sleep the 750M when you unplug (you do not use this machine on
  a commute).
- Auto-layout monitors. After the 750M is awake, use the desktop
  display settings (or `sudo retinaforge-work-displays.sh` to wake +
  list connectors).
- Make a 47 W Haswell 15-inch run cool. Package idle in the 50–70 °C
  range with fans at Apple’s ~2000 RPM floor is normal.
- Auto-switch GPUs on load.
- Tune Wi-Fi, SATA ALPM, or `powertop --auto-tune`.

USB DisplayLink (`present-on`) is occasional presenting and **sleeps**
the 750M on purpose. Do not use that for a native HDMI/TB desk.

## Recreate on Debian

Full Intel-lid + UKI + `force_igd` + Plasma Wayland:
[`recreate.md`](recreate.md), [`debian-workstation.md`](debian-workstation.md).

This power profile is the easy half: copy the repo, run
`install-work-power.sh` as root. Guards are DMI `MacBookPro11,3` and
`fb0` containing `i915`. No CachyOS kernel cmdline required.

## Manual

```bash
sudo retinaforge-power-policy.sh status
sudo retinaforge-power-policy.sh desk      # wake 750M, balanced
sudo retinaforge-power-policy.sh commute   # sleep 750M (manual only)
sudo retinaforge-work-displays.sh          # desk + print DRM connectors
```
