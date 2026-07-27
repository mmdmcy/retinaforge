# Project Handoff

Last updated: 2026-07-24

## Current Position

- The native-first workstation route is proven viable on Big Sur.
- The current packaged baseline and Codex CLI run on the physical Mac.
- Go 1.26.5 has a reproducible compatibility patch and targeted validation.
- Node 24 is the next major native compatibility experiment.
- Linux remains a narrow service boundary, not the default desktop.
- Bare-metal Linux storage research is paused and maintained in this same
  repository (Linux storage workbench / `docs/`, `scripts/`, `patches/`).

## Recent Changes

- Moved the project out of a general research dump into this standalone repo.
- Separated local/private acquisition media, raw captures, build artifacts,
  recovery files, and package bundles from publishable material.
- Rewrote the broad research report as a public workstation plan.
- Added a reproducible Go source-build script and validation record.

## How To Extend Safely

- Keep stable and experimental toolchains side by side.
- Record exact source checksums and deployment targets.
- Use real project tests before declaring a runtime compatible.
- Keep hostnames, addresses, credentials, serials, UUIDs, and raw captures out
  of tracked files.
- Do not resume writable Linux storage experiments without a fresh backup,
  explicit authorization, and the safeguards in the Linux storage workbench docs in this repository.

## Verification Baseline

```bash
bash -n scripts/bootstrap-big-sur-dev.sh
bash -n scripts/build-go-1.26.5-big-sur.sh
bash -n scripts/run-bootstrap.command
git diff --check
```

On the target Mac, rerun the Go build script and compare its targeted tests
with [the recorded validation](go-1.26.5-validation.md).

## Known Loose Ends

- Convert the Go experiment into a local MacPorts Portfile overlay.
- Test Node 24 with MacPorts LLVM and the full relevant test suite.
- Verify a representative Docker Compose workflow against a remote engine.
- Verify QEMU with HVF before relying on an offline local engine.
- Add a concise results table for each real development repository tested.
