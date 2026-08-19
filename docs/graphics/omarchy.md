# Omarchy on this MacBookPro11,3

**Accepted daily (2026-08-19):** stock Omarchy 4 on this chassis.
Hyprland 0.56, lid on **nouveau** at 2880×1800, LUKS2+btrfs, wifi `wl`.
**Leave it.** Do not port `force_igd`. Do not run RetinaForge Intel or
SDDM session installers against this root.

Wrap-up:
[`../source-notes/2026-08-19-omarchy-daily.md`](../source-notes/2026-08-19-omarchy-daily.md).
Durable sync:
[`../source-notes/2026-08-19-omarchy-luks-btrfs-sync.md`](../source-notes/2026-08-19-omarchy-luks-btrfs-sync.md).

Omarchy 4 (“Quattro”) is a Hyprland rice on Arch with a Quickshell
desktop. It is **not** a shortcut around the mux. An Intel lid was
proven on **CachyOS** (2026-08-17). That recipe is archived below. The
live Omarchy desktop does **not** need it.

Cook-book siblings: [`recreate.md`](recreate.md) (layers),
[`hyprland.md`](hyprland.md) (CachyOS Hyprland),
[`intel-first-repro.md`](intel-first-repro.md) (historical Intel panel).

## Ready vs not ready

**Ready (this Omarchy install, 2026-08-19) — do not change:**

- Limine UKI boot, Hyprland 0.56, eDP **2880×1800** on **nouveau**
  (`DIS:+`).
- LUKS2 + btrfs; userspace `fdatasync` ~8 ms.
- BCM4360 with the `wl` module.

**Archived (CachyOS Intel lid, 2026-08-16/17) — do not port unless
explicitly asked:**

- Intel UKI lid: `apple_gmux.force_igd=1` + DDI A 4-lane poke +
  `i915.enable_dc=0` → `i915drmfb`, eDP-2 2880×1800.
- Hyprland 0.56 on `/dev/dri/intel-igpu` with `AQ_NO_ATOMIC=1`.
- Command (⌘) = Super (`hid_apple swap_opt_cmd=0`).
- Hardware snippet: `/usr/local/share/retinaforge/hyprland-retinaforge.lua`.

Stock Arch/Omarchy `apple-gmux` has **no `force_igd`**. That is why the
Intel path is a patched kernel, not a Hyprland setting. The daily
picture does not need it.

## Hard stops

- Do **not** let the installer take the whole internal Apple SSD
  (dedicated-drive wipe). That erases **macOS**.
- Shrink **APFS only from macOS Disk Utility**. Never from Linux.
- Omarchy 4 **defaults to LUKS2**. On this SSD that is acceptable **when
  the filesystem on the mapper is btrfs** (Omarchy’s default). The ~1.1 s
  tax was **ext4-on-dm-crypt**, not LUKS itself. 2026-08-19 userspace
  probe: 64×1 MiB `fdatasync` median 8.4 ms.
  [`2026-08-19-omarchy-luks-btrfs-sync.md`](../source-notes/2026-08-19-omarchy-luks-btrfs-sync.md).
  Do **not** put ext4 on dm-crypt here. Do not disable barriers.
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

## Installer disk map (this 1 TB GPT)

CachyOS trouble on this chassis was almost certainly **boot/ESP**, not
needing a huge swap partition. Omarchy does **not** want a dedicated
swap slice at install. It uses **zram** in RAM. Hibernate is optional
later (`/swap` subvolume = size of RAM, 16 GB here) — skip it on night
one.

Do **not** reuse Apple’s EFI (`disk0s1`, ~210 MB) as Linux `/boot`. It
is too small, and it is macOS. Omarchy wants **one** FAT32 partition
that is both the ESP **and** `/boot` (not `/boot/efi`). Limine puts
kernels next to `limine.conf` there.

Target after the 2026-08-19 APFS shrink and CachyOS delete (the hole the
installer filled; live layout is in section A below):

| Slice | Size | Role |
| --- | --- | --- |
| Apple EFI | 210 MB | macOS only. Do not format. Do not mount as `/boot`. |
| APFS | 80 GB | Big Sur recovery (~45 GB used). |
| **Free** | **~920 GB** | **Omarchy goes only here.** |

### What the installer should create in that ~920 GB hole

| Partition | Size | FS | Mount | Flags |
| --- | --- | --- | --- | --- |
| Omarchy ESP/boot | **2 GiB** (1 GiB is the documented minimum; 500 MB ran out on an Intel Mac) | FAT32 | **`/boot`** | `boot`, `esp` |
| Omarchy root | rest of the hole | **LUKS2** → btrfs, `compress=zstd` | subvolumes below | Linux filesystem |
| swap partition | **none** | — | zram | — |

Btrfs subvolumes Omarchy expects:

| Subvolume | Mount |
| --- | --- |
| `@` | `/` |
| `@home` | `/home` |
| `@log` | `/var/log` |
| `@pkg` | `/var/cache/pacman/pkg` |

Omarchy 4 **turns LUKS2 on** unless you `Ctrl+C` the format/encryption
confirm (the disk-pick confirm is not that toggle). **Keep that
default.** **btrfs on LUKS2** is the stack that stayed
millisecond-class here; **ext4 on dm-crypt** is the stack that paid
~1.1 s. Recreate:
[`2026-08-19-omarchy-luks-btrfs-sync.md`](../source-notes/2026-08-19-omarchy-luks-btrfs-sync.md).

Bootloader: **Limine**, onto **that new 2 GiB `/boot`**, not the USB
and not Apple EFI. If the ISO offers **Free space install (alongside
existing data)**, that is the **~920 GB** gap — confirm the summary
does **not** list the whole 1 TB disk or the 80 GB APFS.

Classic installer errors from last time:

| Message | Actual cause |
| --- | --- |
| Boot partition not found / ESP not found | `/boot` missing, or FAT32 lacks **both** `boot` and `esp`, or you mounted `/boot/efi` instead of `/boot` |
| No valid Limine configurations | `/boot` too small (use 2 GiB) or Limine installed to the USB |
| Whole disk wiped | “Default partitioning layout” on the Apple SSD |

CachyOS is already gone from this disk (2026-08-19). Option-boot macOS
is the remaining local recovery. First Omarchy boot is NVIDIA/`nouveau`
on the lid — that is the accepted daily.

The working Intel UKI was copied onto the Mac APFS data volume before
the shrink (not in git). Archived recipe only.

## Two install shapes

### A. Landed on this disk (2026-08-19)

Free-space install into the hole after the APFS shrink. CachyOS is
gone. Live Linux slices (sizes rounded):

| Slice | Size | Role |
| --- | --- | --- |
| Apple EFI | 200 MiB vfat | macOS only |
| APFS | ~75 GiB | Big Sur recovery |
| Omarchy `/boot` | 2 GiB vfat | ESP + kernels (`boot`+`esp`) |
| Omarchy root | ~855 GiB LUKS2 → `omarchy_root` btrfs | `@` `/`, `@home`, `@log` |

Never “the whole disk.” First boot is NVIDIA/`nouveau` at 2880×1800 —
that is the **accepted daily**, not a gap. Durable sync on that btrfs
home stayed ~8 ms (see the 2026-08-19 notes). If you reinstall, choose
**only** leftover free space, keep LUKS2+btrfs, do not put ext4 on the
mapper. Do not port `force_igd` unless explicitly asked.

### B. Keep CachyOS (not this machine anymore)

CachyOS was removed here so Omarchy could take the Linux space. Fun-only
Omarchy on a spare disk/VM is still the path if you are not ready to
port `force_igd`.

## After an Omarchy userspace exists (archived — do not run)

The live daily is stock nouveau. The steps below were the **CachyOS
Intel port**. They stay written so the science is not lost. **Do not
run them** on the accepted Omarchy root.

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
