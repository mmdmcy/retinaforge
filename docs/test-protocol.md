# Apple AHCI Latency Test Protocol

This protocol measures durable-write latency without a destructive benchmark.
It is designed for the encrypted root filesystem and must not be used to test
boot changes unattended.

## Preconditions

- The system has been idle for at least two minutes after package operations.
- CPU temperature is below 75°C and the system has no active package manager.
- The current kernel remains selectable in GRUB before any candidate boot.
- Test files are created only under `/var/tmp` on the same filesystem as `/`.
- For the NCQ candidate, the command line lacks `libata.force=noncq` and queue
  depth is greater than one. For the separate FUA candidate,
  `/sys/block/sda/queue/fua` must additionally report `1`.

## Baseline Probe

Run from the repository checkout on the target:

```bash
scripts/run-latency-probe.sh --yes --size-mib 16
```

The probe writes at most the requested size, calls `fdatasync()` at the chosen
interval, emits percentile and maximum latency, and removes its temporary data
directory even on interruption. It refuses a directory mounted on a different
filesystem from `/`.

## Optional Block Trace

For an ATA request trace, run the same bounded probe as root and place output
under an ignored local capture directory:

```bash
sudo scripts/run-latency-probe.sh --yes --size-mib 16 \
  --trace-out captures/ncq-on.trace
```

The script temporarily enables only block request issue/complete tracepoints,
then restores their prior state. Do not commit the trace file.

Summarize an ignored trace locally with:

```bash
scripts/summarize-block-trace.py captures/ncq-on.trace
```

## Acceptance Gate

Compare a candidate against the `noncq` baseline only after the same test
finishes successfully:

- no individual sync request exceeds one second;
- p99 sync latency is below 100 ms for the bounded probe;
- I/O `full` pressure does not remain elevated after the probe completes;
- no ATA reset, timeout, or filesystem error appears in the current boot log;
- a normal package/write workload remains responsive over SSH and locally.

If a candidate fails boot or unlock, select the unchanged stock entry. Do not
edit LUKS, filesystem, or hardware settings as a recovery shortcut.
