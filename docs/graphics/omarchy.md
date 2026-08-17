# Omarchy on this MacBookPro11,3

Omarchy 4 (“Quattro”) is a Hyprland rice on Arch with a Quickshell
desktop. It is **not** a shortcut around the mux. Hyprland already
modesets this Intel lid on CachyOS (2026-08-17). What Omarchy still has
to inherit is the **same lid recipe**, then a Lua hardware pin so their
rice keeps its looks.

Cook-book siblings: [`recreate.md`](recreate.md) (layers),
[`hyprland.md`](hyprland.md) (what we proved),
[`intel-first-repro.md`](intel-first-repro.md) (why the panel is 2880×1800).

## Ready vs not ready

**Ready (proven on this chassis, 2026-08-17):**

- Intel UKI lid: `apple_gmux.force_igd=1` + DDI A 4-lane poke +
  `i915.enable_dc=0` → `i915drmfb`, eDP-2 2880×1800.
- Hyprland 0.56 on `/dev/dri/intel-igpu` with `AQ_NO_ATOMIC=1`.
- Command (⌘) = Super (`hid_apple swap_opt_cmd=0`).
- Hardware snippet: `/usr/local/share/retinaforge/hyprland-retinaforge.lua`.

**Not ready until you do it on the Omarchy root:**

- A kernel whose `apple-gmux` has `force_igd`
  (`modinfo apple-gmux | grep force_igd`). Stock Arch/Omarchy kernels
  usually **do not**.
- An **EFI-stub / UKI** boot of that kernel (GRUB `linux` skipped
  `apple_set_os()` here).
- The DDI poke **before** i915, then `check-intel-first-panel.sh`.

If those three are missing, Omarchy’s Hyprland never sees a 2880×1800
mode. The ISO looking pretty on another laptop does not change that.

## Hard stops

- Do **not** let the installer take the whole internal Apple SSD
  (dedicated-drive wipe). That erases **macOS**.
- Shrink **APFS only from macOS Disk Utility**. Never from Linux.
- Skip **LUKS** on this SSD (lab: ext4-on-dm-crypt ~1.1 s durable sync
  tails). Omarchy defaults to encryption; `Ctrl+C` the format confirm
  or pick unencrypted ext4/btrfs.
- Quattro’s “dual-boot when free space exists” text is aimed at
  **Windows + BitLocker**. This machine is **APFS + Linux**. Free space
  must already exist, created from macOS, and the installer must use
  **only that** (or the existing CachyOS partition if you are replacing
  Linux).
- No live `echo IGD` / `DIS`. No `i915.enable_dc=1`. No TLP.
- Do not run `enable-wayland-intel.sh` on Omarchy. That script is
  **SDDM** autologin (Plasma / `hyprland-intel`). Omarchy is its own
  session. Use `recreate-desktop.sh omarchy` instead.

Keep a bootable Big Sur APFS even if you never log in. When a Linux
graphics experiment blacks the lid, Option / Startup Manager is the
recovery that SSH cannot replace.

## Two install shapes

### A. Replace CachyOS, keep macOS (likely what you mean)

1. Confirm macOS still boots (Option). Time Machine / clone first if
   anything on the Linux partition matters.
2. From macOS Disk Utility, confirm the Linux partition vs APFS. Shrink
   APFS **only** if you need a larger Linux slice.
3. Boot the Omarchy 4 ISO. Choose **only** the existing Linux partition
   (or the pre-shrunk free space). Never “the whole disk.” Skip LUKS.
4. First boot may be a **black lid**. That is expected if the stock
   kernel has no `force_igd`. SSH from another machine if you already
   enabled it; otherwise boot macOS.
5. On the Omarchy root, port the lid (next section), then the Lua pin.

### B. Keep CachyOS (Hyprland already works)

You do not need Omarchy to “get Hyprland.” Fun-only Omarchy belongs on a
**spare disk or VM** until path A has a passing
`check-intel-first-panel.sh`.

## After an Omarchy userspace exists

Order matters. Skip a layer and the next one is meaningless.

```bash
# 1. Kernel: apple-gmux must expose force_igd. Carry linux-cachyos, or
#    an out-of-tree apple-gmux, or a patched Arch kernel. Then:
modinfo apple-gmux | grep force_igd   # must print a parm

# 2. Userspace lid + DRM pin (no SDDM rewrite):
sudo ./scripts/graphics/recreate-desktop.sh omarchy

# 3. Rebuild an EFI-stub / UKI with
#    apple_gmux.force_igd=1 i915.enable_dc=0 modprobe.blacklist=i915
#    CachyOS helper (if mkinitcpio + Limine still exist):
#    sudo SKIP_LIMINE=1 ./scripts/graphics/build-apple-set-os-uki.sh
#    Else: debian-ukify-intel.sh pattern in recreate.md (ukify).
#    Point the firmware boot at that UKI, not GRUB linux.

# 4. Reboot the UKI. Then:
sudo ./scripts/graphics/check-intel-first-panel.sh
```

When the checker is green, pin Hyprland. Omarchy 4’s entry file is
`~/.config/hypr/hyprland.lua`. Add this **last** so it wins over
Omarchy’s `preferred` / `scale = auto` monitor rule:

```lua
dofile("/usr/local/share/retinaforge/hyprland-retinaforge.lua")
```

Leave Omarchy’s `bindings.lua`, Quickshell, and theme alone. Do **not**
point the session at `hyprland-intel.conf` (CachyOS waybar/wofi binds).

Optional, in `~/.config/hypr/monitors.lua`, make the lid explicit
instead of relying only on the dofile:

```lua
hl.monitor({
  output = "eDP-2",
  mode = "2880x1800@59.99",
  position = "0x0",
  scale = 2,
})
```

Command as Super is `/etc/modprobe.d/retinaforge-hid-apple.conf`
(`swap_opt_cmd=0`, `fnmode=1`), installed by `install-wayland-intel.sh`.
Do not set xkb `applealu_iso` + `mac` — that fights the hid map.

Verify as the **seated user** (root `Hyprland --verify-config` can abort
while a session is running):

```bash
Hyprland --verify-config --config ~/.config/hypr/hyprland.lua
```

`check-wayland-intel.sh` still applies: seat0 `Type=wayland`, compositor
on Iris Pro, eDP enabled.

## What the Lua snippet owns

`/usr/local/share/retinaforge/hyprland-retinaforge.lua`:

| Piece | Why |
| --- | --- |
| `AQ_DRM_DEVICES=/dev/dri/intel-igpu` | Aquamarine cannot parse colons in `by-path` |
| `AQ_NO_ATOMIC=1` | Same Haswell eDP that timed out KWin atomic |
| `eDP-2` 2880×1800@59.99 scale 2 | The working mode; `scale=auto` is a guess |
| `kb_layout=nl`, `kb_model=pc105` | Dutch ISO, Command already Super via hid |
| blur off | Haswell Iris Pro |
| brightness via `retinaforge-brightness` | `gmux_backlight`, not a random backlight node |

Volume, launcher, bar, and theme stay Omarchy’s.

## If the lid is black after the ISO

1. Boot macOS (Option). Confirm the panel still works.
2. Do not send `IGD`/`DIS` from a running Linux.
3. Confirm the Omarchy kernel: `modinfo apple-gmux | grep force_igd`.
   Empty output means you are not done; the rice cannot light this
   panel.
4. Recovery Limine **NVIDIA LTS** is a CachyOS entry. After a replace
   install it may be gone. macOS is then the only local display.

## Related

- [`hyprland.md`](hyprland.md) — CachyOS Hyprland binds + 0.56 overlay.
- [`max-value-and-omarchy.md`](max-value-and-omarchy.md) — 750M, Steam, keep macOS.
- [`wayland.md`](wayland.md) — Plasma Wayland / SDDM traps (not Omarchy).
