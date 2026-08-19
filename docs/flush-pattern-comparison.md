# Darwin vs Linux Flush / Command-Pattern Comparison

Goal: explain why this `APPLE SSD SM1024F` completes Big Sur
`F_FULLFSYNC` in milliseconds while Linux stock AHCI holds
`ATA_CMD_FLUSH_EXT` for ~1.1 s (`ci_held`) under the filesystem-stack
workload. Same internal SSD. No replacement drive. No barrier disable.
No writable MSI+NCQ.

## Already closed

| Fact | Evidence |
| --- | --- |
| Linux post-issue flush delay | legacy + flush-reg captures |
| Long flushes keep `PxCI` set | `ci_held` on all 26 long flushes |
| Big Sur strict sync can be fast | prior isolated `F_FULLFSYNC` ~7-13 ms |

## Harness

### Linux (host, offline on existing captures)

```sh
python3 scripts/extract-flush-pattern.py \
  captures/2026-07-30-flush-reg-physical/controller-state.txt \
  --json > /tmp/linux-flush-pattern.json
python3 scripts/extract-flush-pattern.py \
  captures/2026-07-30-flush-reg-physical/controller-state.txt
```

### Darwin (on the Mac, internal APFS)

Copy `tools/macos-flush-pattern-probe.c` to the Mac:

```sh
clang -O2 -Wall -Wextra macos-flush-pattern-probe.c -o macos-flush-pattern-probe
./macos-flush-pattern-probe "$HOME" 64 1024 64 | tee darwin-flush-pattern.txt
```

Modes:

- `isolated-*` — fresh file per sample (legacy probe shape)
- `sustained-F_FULLFSYNC` — one file, 64× (1 MiB write + `F_FULLFSYNC`)
- `flush-only-F_FULLFSYNC` — write 64 MiB once, then 64 syncs with no more writes

Sanitize serials before copying anything into the repo. Keep the raw log
private or redacted.

### Compare

```sh
python3 scripts/compare-flush-patterns.py \
  --linux-json /tmp/linux-flush-pattern.json \
  --darwin-log darwin-flush-pattern.txt
```

## How to read the table

| If Darwin sustained stays ms-fast and Linux has ~1.1 s tails | Next |
| --- | --- |
| Yes | Linux write+flush mix / FS pattern is the lead; design one Linux probe that approaches Darwin’s cadence/mix |
| No, Darwin also grows ~1 s tails | Compare entry points (which sample index / preceding write volume); shared device mode, not Linux-only IRQ myth |
| Darwin flush-only stays fast, sustained slows | Intervening writes matter on Darwin too; match that on Linux deliberately |

## Linux baseline already extracted

From `captures/2026-07-30-flush-reg-physical/` (flush-reg-stack, pass):

- `ATA_CMD_FLUSH_EXT`: 112
- `ATA_CMD_FPDMA_WRITE`: 571
- long flushes (≥100 ms): 26, all `ci_held`
- flush completion p50 ~18 ms, p95 ~1.133 s
- first long flush appears after earlier short flushes (slow mode is entered, not always-on)

## Darwin result (2026-07-30, SSH on Big Sur APFS)

From `captures/2026-07-30-darwin-flush-pattern/` (private):

- sustained `F_FULLFSYNC` 64×1 MiB: median 6.323 ms, p95 6.850 ms, max 11.046 ms, **0** long syncs
- flush-only after 64 MiB write: median 0.003 ms, max 20.640 ms, **0** long syncs

Darwin did **not** enter the ~1.1 s mode. Next step is a Linux sustained
write+`fdatasync` mirror on the scratch partition, not more Darwin probing.

## Later userspace check (2026-08-19)

Omarchy 4 LUKS2+btrfs home, 64×1 MiB `fdatasync`: median 8.4 ms, max
15 ms, 0 long tails. Same SSD. Not a new AHCI capture.
[`source-notes/2026-08-19-omarchy-luks-btrfs-sync.md`](source-notes/2026-08-19-omarchy-luks-btrfs-sync.md).
