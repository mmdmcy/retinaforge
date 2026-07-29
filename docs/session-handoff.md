# Session Handoff

## Current Direction

Native Linux on the original Apple SSD is the active route. Windows graphics
work is archived as hardware evidence, not an active implementation path. Do
not replace the SSD, weaken durable-write semantics, or treat an external SSD
as a solution for the intended installation.

Use a designated stronger Linux build host for kernel compilation. Keep a
low-resource controller for source review, manifests, and small checks only.
The repository is intended to be cloned normally on the build host; ignored
`build/` artifacts are reproducible and are not transferred between hosts.

## Latest Host-Validated Artifact

The read-only direct-EFI Linux Intel-enumeration appliance was built from the
authenticated Linux `v7.1.3` source commit
`199c9959d3a9b53f346c221757fc7ac507fbac50`.

```text
artifact: build/linux-igpu-readonly-v7.1.3/artifact/
kernel:   bb42109c8465de1f141b75deb1307626095b82f4dfb0326a979ad5ed00a898fb
EFI stub: d2888d105727f622f34bb174e3cdf14e2aaa56a3e7e792bcea6bfdbe921a6f93
```

The manifest, direct-EFI PE format, and built-in `i915`, `apple-gmux`,
framebuffer, and VGA-switcheroo configuration checks passed. This is only a
host artifact. It has not been provisioned to removable media or booted on the
MacBook.

To reproduce it on the designated Linux build host, install the dependencies
reported by the builders, prepare the authenticated source, then build:

```bash
scripts/prepare-kernel-source.sh
CLEAN=1 JOBS="$(nproc)" scripts/build-linux-igpu-readonly-probe.sh
```

Do not start a new build merely as a routine check. Rebuild only after a source
or appliance change, or when a freshly verified removable-media artifact is
explicitly needed.

## Physical-Test Boundaries

- No USB, internal SSD, EFI variable, GMUX, boot-order, or panel-routing action
  is authorized without an explicit user-present request.
- The current lab USB's last verified payload is the archived Windows
  Intel-enumeration probe. It must be deliberately reprovisioned for Linux;
  never assume it contains recovery media or a Linux artifact.
- The guarded strict-flush trace intentionally refuses to run until an approved
  disposable `MBPTEST` partition exists on the internal SSD. No such partition
  exists now.
- A successful Intel enumeration does not prove internal-panel ownership,
  discrete-GPU rail-off, suspend/resume, or a safe permanent Linux install.
- Preserve direct Big Sur and direct Windows boot paths as recovery references.

## Next Engineering Work

1. On the stronger Linux host, inspect the checked-out source and dependencies
   without rebuilding. Keep the host workspace clean and use ignored `build/`
   output there.
2. Complete host-only validation for the Intel-enumeration artifact and review a
   separate guarded Linux USB writer and user-present procedure. The writer
   must identify one removable whole disk, require an exact confirmation token,
   verify source and readback checksums, and leave the internal disk untouched.
3. Keep the graphics boot separate from the storage experiment. Its first
   physical run is read-only and records GPU binding, connector, backlight, PCI
   power, and VGA-switcheroo state only.
4. Only after separate approval and a verified recovery route, create the
   temporary scratch partition needed for the existing legacy-INTx strict-flush
   trace. Use its timing result to choose the next storage investigation.

Read [`linux-native-roadmap.md`](linux-native-roadmap.md) before making a
hardware change. The Windows archive is at
[`archive/windows/README.md`](archive/windows/README.md).
