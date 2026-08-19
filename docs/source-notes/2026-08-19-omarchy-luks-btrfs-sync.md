# Omarchy LUKS2 + btrfs: userspace durable sync stays millisecond-class (2026-08-19)

## Abstract

Omarchy 4’s free-space install applied **LUKS2 by default** (easy to miss:
the disk-pick confirm is not the encryption opt-out; that is `Ctrl+C` on
the format/encryption step). The live root is LUKS2 (`aes-xts-plain64`,
512-bit) with **btrfs** (`compress=zstd:3,ssd,noatime,space_cache=v2`).

A Darwin-mirror userspace probe on that home volume (1 MiB write +
`fdatasync` / `fsync`, 12 then 64 samples) did **not** reproduce the
~1.1 s tails from the 2026-07 **ext4-on-dm-crypt** stack. Median
`fdatasync` was **8.4 ms**, max **15 ms**, **0** samples ≥100 ms.

This is a **filesystem-on-crypt** result, not a claim that the AHCI
`FLUSH CACHE EXT` / `ci_held` mechanism is gone. It matches the 2026-07-30
split: dm-crypt **raw** was already fast; the tax appeared when **ext4
ran on the mapper**.

## Stack (what to recreate)

| Piece | This boot |
| --- | --- |
| Distro | Omarchy 4.0.0 (`ID_LIKE=arch`) |
| Kernel | `7.1.8-arch1-3` (stock Arch, legacy INTx / no-MSI quirk still in play) |
| Mapper | LUKS2 on the Linux root partition |
| Filesystem | btrfs subvolumes `@` `/`, `@home` `/home` |
| Mount | `rw,noatime,compress=zstd:3,ssd,space_cache=v2` |
| Swap | zram (~RAM size), not a disk swap partition |
| Probe | `tools/linux-fdatasync-probe.py` on a directory on the mapper (not tmpfs `/tmp`) |

Do not copy hostnames, usernames, mapper UUIDs, or SSIDs into this file.

## Numbers

Same 1 MiB rewrite + durable sync shape as
[`docs/findings.md`](../findings.md) (2026-07-30 stack table).

| Probe | n | median sync | max | ≥100 ms |
| --- | ---: | ---: | ---: | ---: |
| Lab dm-crypt+**ext4** `fdatasync` | 12 | 1.137 s | 1.154 s | all |
| Lab dm-crypt **raw** (no FS) | 12 | 9.557 ms | 26.4 ms | 0 |
| Lab plain ext4 `fdatasync` | 12 | 11.7–18.8 ms | ~19 ms | 0 |
| **Omarchy LUKS2+btrfs `fdatasync`** | 12 | **9.1 ms** | 9.4 ms | **0** |
| **Omarchy LUKS2+btrfs `fdatasync`** | 64 | **8.4 ms** | 15 ms | **0** |
| Omarchy LUKS2+btrfs `fsync` | 64 | 5.5 ms | 13 ms | 0 |
| Big Sur `F_FULLFSYNC` (64×1 MiB) | 64 | 6.3 ms | 11 ms | 0 |

Writes themselves stayed ~0.3–0.4 ms.

## What this is not

- Not a block/libata trace. No `ATA_CMD_FLUSH_EXT` / `PxCI` samples on
  this boot. The 2026-07 `ci_held` ~1.1 s flushes remain a real mechanism
  on this SSD under the **ext4-on-crypt** (and some heavy cleanup) paths.
- Not “Omarchy patched the Samsung AHCI.” Same `144d:1600` family, no
  MSI+NCQ experiment, barriers still on.
- Not proof that a git/DB/`fdatasync` storm cannot re-enter slow flush.
- Not a claim that nouveau is a bug. The accepted daily lid is
  **nouveau** (`DIS:+`). `force_igd` stays an archived CachyOS recipe.

## What made it work (the recreatable fix)

The slow path was **ext4 on dm-crypt**, not encryption itself. The
working daily root is:

1. **LUKS2** on the Linux data partition (`aes-xts-plain64`, 512-bit).
2. **btrfs** on that mapper (`compress=zstd:3,ssd,noatime,space_cache=v2`),
   not ext4.
3. Durable writes probed on a **real home directory** on that volume
   (`tools/linux-fdatasync-probe.py`), not tmpfs `/tmp`.

That stack stayed in the same millisecond neighborhood as Big Sur
`F_FULLFSYNC` and as the 2026-07 dm-crypt-raw / plain-ext4 probes.

What did **not** fix it (do not “help” by doing these):

- skipping LUKS as a hard rule
- putting ext4 on the mapper
- disabling barriers / write cache
- re-enabling MSI+NCQ
- assuming a newer distro kernel patched `FLUSH_EXT`

## Policy change

**Skip LUKS** is no longer a hard requirement for “usable durable sync”
on this chassis **if the filesystem on the mapper is btrfs** (Omarchy
defaults) rather than ext4. Prefer not to put **ext4 on dm-crypt** here.
Do not disable barriers or re-enable MSI+NCQ to “make LUKS fine.”

Omarchy 4 will still turn LUKS on unless you abort the encryption
confirm. That default is acceptable for this SSD given this probe.

## Recreate the probe

```bash
python3 tools/linux-fdatasync-probe.py "$HOME" 64
```

`$HOME` must be on the btrfs/LUKS volume, not tmpfs.
