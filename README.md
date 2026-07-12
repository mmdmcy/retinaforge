# Apple AHCI Linux Workbench

An open, reproducible workbench for investigating severe write-latency stalls
on Intel Apple laptops with Apple/Samsung PCIe AHCI storage controllers.

The project starts with Ubuntu and Linux Mint because they provide a stable
kernel and packaging baseline. Debian, Fedora, and Arch can use the same
reproduction and validation harness later; changing distributions alone is not
assumed to change the underlying `ahci` driver path.

## Goal

Make affected machines usable as normal work laptops under Linux:

- bounded storage latency during ordinary application writes;
- no desktop-wide freezes while package managers or journals write;
- a supported, updateable Ubuntu/Mint kernel path;
- controller-specific configuration or kernel quirks that are explicit,
  reproducible, and reversible.

## Current working hypothesis

Some Apple/Samsung controllers expose a standard AHCI interface but behave
poorly under Linux write concurrency. Generic SMART health can remain clean
while the Linux block stack experiences prolonged request latency.

This repository does not assume a failing SSD, does not disable filesystem
integrity guarantees as a default, and does not treat a new Linux distribution
as a fix until it demonstrates a different result.

## Repository layout

- `scripts/collect-controller-state.sh` — sanitized controller-state capture.
- `docs/architecture.md` — the storage-path model and boundaries.
- `docs/experiment-plan.md` — the staged validation and patch plan.
- `patches/` — proposed and validated kernel patches.

## First target

The first target is an Intel MacBook Pro with an Apple/Samsung AHCI SSD
controller, using an Ubuntu 24.04 / Linux Mint base and a supported 6.8 LTS
kernel track.

No raw machine captures belong in this repository. The collector redacts serial
numbers by default; keep full captures locally under an ignored directory.

## Safety rules

1. One controller or kernel variable changes per experiment.
2. Keep a known-good kernel boot entry before testing a new one.
3. Never use a destructive benchmark against the root filesystem.
4. Do not publish hostnames, IP addresses, serial numbers, encryption metadata,
   private logs, or raw conversation transcripts.
5. A proposed solution is not accepted until it improves measured tail latency
   and real desktop responsiveness.

## Status

Initial scaffold. The next implementation milestone is a bounded block-I/O
latency trace and a reversible Apple-AHCI performance profile.
