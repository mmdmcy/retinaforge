# Experiment Plan

## Acceptance criteria

A change is accepted only when all of the following improve:

- no sustained desktop-wide I/O stalls during an ordinary write workload;
- lower tail block-request latency in the trace;
- application and package-manager responsiveness remains usable;
- the machine still boots with a documented recovery entry;
- SMART and kernel logs show no new storage errors.

## Sequence

### 1. Baseline trace

Capture a sanitized controller state plus block request latency while running a
small, bounded write workload. Do not run destructive or multi-gigabyte root
filesystem benchmarks.

### 2. Runtime profile experiments

Test one change at a time and restore the baseline between tests:

1. `max_performance` SATA link power policy.
2. `none` versus `mq-deadline` block scheduler.
3. Small request-queue limits to protect desktop latency.

### 3. Boot-time controller experiments

After a tested recovery entry exists, test PCIe ASPM and AHCI power-management
parameters one at a time.

### 4. Kernel quirk

If the trace still shows controller-level latency, add a narrow quirk for the
controller PCI ID to the Ubuntu/Mint kernel source. Keep it as a small patch in
`patches/`, build a test kernel package, and validate it with the same trace.

### 5. Filesystem and encryption comparison

Only after the controller path is stable, compare encrypted and unencrypted
storage using a non-destructive test volume. Do not remove LUKS merely to mask
an AHCI stall.
