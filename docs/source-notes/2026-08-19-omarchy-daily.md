# Omarchy 4 accepted as the daily Linux (2026-08-19)

## Verdict

On this `MacBookPro11,3`, **stock Omarchy 4 is the daily Linux**. Leave
it alone. Do not port `force_igd`, do not run RetinaForge Intel/Hyprland
installers against it, do not live-mux, do not reinstall to drop LUKS.

CachyOS was replaced in free space after an APFS shrink. macOS Big Sur
stays on a small APFS slice as local recovery. Never a whole-disk ISO.

Public siblings: [`omarchy.md`](../graphics/omarchy.md),
[`2026-08-19-omarchy-luks-btrfs-sync.md`](2026-08-19-omarchy-luks-btrfs-sync.md),
[`gaming-and-retina.md`](../graphics/gaming-and-retina.md).

Do not copy hostnames, usernames, addresses, keys, SSIDs, or mapper
UUIDs into this file.

## What landed (sanitized)

| Slice | Role |
| --- | --- |
| Apple EFI (~200 MiB vfat) | macOS only. Not Linux `/boot`. |
| APFS (~75 GiB) | Big Sur recovery (shrunk from macOS Disk Utility). |
| Linux ESP (~2 GiB vfat) | Omarchy `/boot` + ESP (`boot`+`esp`). Limine UKI. |
| Linux data (~855 GiB LUKS2 → btrfs) | `@` `/`, `@home` `/home`, `@log` `/var/log` |

Swap is **zram** (plus an unused swapfile Omarchy created). No disk swap
partition. Installer used **only leftover free space**.

## Storage (the recreatable fix)

The ~1.1 s durable-sync tax on this SSD was **ext4 on dm-crypt**, not
LUKS itself. Omarchy’s default **LUKS2 + btrfs**
(`compress=zstd:3,ssd,noatime`) stayed millisecond-class:

- 64×1 MiB `fdatasync`: median **8.4 ms**, max **15 ms**, **0** ≥100 ms

That matches Big Sur `F_FULLFSYNC` and the 2026-07 dm-crypt-raw / plain
ext4 probes. Not an AHCI / `FLUSH_EXT` patch. Do not put ext4 on the
mapper. Do not disable barriers. Do not re-enable MSI+NCQ.

Probe: `tools/linux-fdatasync-probe.py` on a directory on the mapper,
not tmpfs. Full table:
[`2026-08-19-omarchy-luks-btrfs-sync.md`](2026-08-19-omarchy-luks-btrfs-sync.md).

## Graphics (leave stock)

Stock Omarchy boots a Limine **UKI** (`protocol: efi`). The lid is
**nouveau** / mux `DIS:+` at **2880×1800@60**, Hyprland 0.56, scale 2.
Iris Pro enumerates (`i915` loaded) but has **no DRM connectors**. Stock
`apple-gmux` has **no `force_igd`**. BCM4360 wifi used the `wl` module
out of the box.

Idle on AC (read-only, ~30 min up): package ~60 °C, 750M ~53 °C, fans at
Apple’s ~2000 RPM floor. Normal for this 47 W 15-inch with both GPUs
powered. Journal had no errors in the sample window.

The Intel-lid recipe (`force_igd` + DDI A 4-lane poke + delayed i915) is
**proven on CachyOS** (2026-08-16/17) and remains documented. It is
**not** the daily Omarchy path. Porting it needs a patched kernel, a
careful UKI, black-lid risk, and only helps heat if the 750M is then
slept (lid-only). HDMI/TB stay on the 750M either way. Decision:
**do not port.**

Hard stops unchanged: no live `IGD`/`DIS`, no `i915.enable_dc=1`, no
TLP, no `enable-wayland-intel.sh` on this rice.

## Games on this boot

The 750M **owns the panel**, so native **OpenGL** uses nouveau
directly. Do not use `DRI_PRIME` / “Run on 750M” (that was Intel-lid
offload). No `vulkan-nouveau` ICD on the stock image; Intel HasVK is
present but is not a 2026 Proton box. Proprietary nvidia 470 left with
CachyOS.

Play 2013-era **native Linux OpenGL** at 1920×1200 or 1440×900, not
native 2880×1800. List: [`gaming-and-retina.md`](../graphics/gaming-and-retina.md).

## What “do not touch” means

- No `force_igd` / DDI / `recreate-desktop.sh omarchy` / Lua `dofile`.
- No whole-disk reinstall. No panic drop of LUKS.
- No writable MSI+NCQ. No barrier disable.
- Keep macOS. Option-boot is local recovery (CachyOS NVIDIA LTS is gone).

Intel cook-book, if anyone ever needs the historical path:
[`intel-first-repro.md`](../graphics/intel-first-repro.md).
