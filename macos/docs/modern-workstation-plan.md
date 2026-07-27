# Modern Development Workstation Plan

- Checked: `2026-07-24 Europe/Amsterdam`
- Target: `MacBookPro11,3`, macOS Big Sur `11.7.11`
- Status: native-first feasibility proven; compatibility work continues

## Decision

The Late-2013 15-inch Retina MacBook Pro is worth keeping as a modern
terminal-first development machine.

The recommended route is:

1. preserve Big Sur as the known-good host;
2. use MacPorts for the maintained native baseline;
3. compile newer runtimes natively when the required APIs can be restored with
   narrow, reviewable compatibility changes;
4. keep source-built versions isolated and tested against real repositories;
5. use a remote Linux engine for containers;
6. add a small headless local Linux VM only when offline containers or
   Linux-specific tests are necessary;
7. test OpenCore Legacy Patcher from an external disk only if a required GUI
   application creates a hard blocker;
8. do not replace Big Sur with Windows merely to modernize the development
   environment.

The machine remains unsupported by Apple and will require more maintenance
than current hardware. That does not prevent it from being useful.

## Hardware Position

The tested machine has:

- a quad-core/eight-thread Intel Core i7-4960HQ;
- 16 GB RAM;
- a 1 TB Apple SSD;
- Intel VT-x and macOS Hypervisor.framework support;
- a 15-inch 2880x1800 display;
- Intel Iris Pro and NVIDIA GT 750M graphics.

The practical limits are operating-system support, battery age, old graphics,
and controller-specific Linux behavior. CPU, memory, and storage remain enough
for substantial terminal development and moderate native compilation.

## Proven Native Baseline

The following versions ran on the physical machine:

| Tool | Observed version |
| --- | --- |
| Git | 2.55.0 |
| Node.js | 22.22.2 |
| npm/npx | 10.9.8 |
| Python | 3.13.14 |
| pip | 26.0.1 |
| Rust | 1.97.1 |
| Cargo | 1.97.0 |
| Go | 1.24.8 |
| CMake | 3.31.12 |
| Ninja | 1.13.2 |
| Neovim | 0.12.4 |
| ripgrep | 15.2.0 |
| fd | 10.4.2 |
| jq | 1.8.2 |

Current native Rust, C, Node, and Python smoke builds passed. The current Codex
CLI package also ran natively and reported `codex-cli 0.145.0`.

## Why Native Compilation Is Viable

Projects often raise their minimum macOS version because that is the oldest
host they build and test, not because every part of the program immediately
depends on newer kernel or framework behavior.

There are three possible outcomes:

1. the source already compiles and runs when given a lower deployment target;
2. a small number of newer APIs need compatible older equivalents;
3. the project fundamentally depends on unavailable kernel, framework,
   compiler, or C++ standard-library behavior.

Only the first two are good compatibility-build candidates. The third belongs
on a newer host or behind the Linux boundary.

Go 1.26.5 was a successful case. The official source built through bootstrap,
but the resulting binary targeted macOS 12 and imported a Monterey-only
Security framework symbol. Restoring the older certificate-chain API and
setting the Mach-O target to macOS 11 produced a working Big Sur binary. See
[the validation record](go-1.26.5-validation.md).

Node 24 is a harder next target. Its current build requirements include a much
newer compiler and C++20 standard library. The next evidence-driven experiment
is an isolated build with a current MacPorts LLVM toolchain; success must be
decided by Node's tests and real project tests.

## What MacPorts Does

MacPorts is a source package manager with a controlled prefix at `/opt/local`.
A port definition records source URLs, checksums, dependencies, compiler
choices, patches, configuration, build steps, and activation.

The installation can look unfamiliar because it installs a parallel Unix
software environment rather than modifying Apple's system files. That
separation is useful on an old Mac:

- system tools remain untouched;
- packages can select newer compilers and libraries;
- unsupported hosts can fall back from a missing binary archive to a local
  source build;
- maintainers can carry compatibility patches;
- `legacy-support` can provide wrappers for APIs missing from old macOS.

The same mechanisms are available to this project through a local Portfile
overlay. MacPorts is not doing something impossible for an individual
developer; it is providing reproducible packaging, dependency resolution,
shared patches, and ongoing maintenance.

## Container Strategy

The Docker terminal client is enough for normal CLI use, but a Docker Engine
still needs a Linux kernel. Docker Desktop is one bundled way to provide that
kernel through a VM; it is not required.

Preferred route:

1. install the Docker CLI and Compose/buildx clients natively;
2. connect over SSH to a trusted Linux Docker Engine;
3. keep editing, Git, Codex, and source files on the Mac;
4. run only container builds and Linux workloads remotely.

Offline fallback:

1. install QEMU through MacPorts;
2. create a headless x86-64 Linux VM with HVF acceleration;
3. allocate about 4 vCPUs, 8 GB RAM, and a sparse 100-150 GB disk;
4. install only SSH, Docker Engine, and genuinely Linux-specific test tools.

This VM is infrastructure, not another desktop.

## Windows And Newer macOS

Windows 10 is no longer a good long-term supported host. Windows 11 is
unsupported on this model without bypassing hardware requirements. Either
route would introduce driver and maintenance uncertainty without improving
the already-working native Unix workflow.

The exact Linux SSD latency should not be assumed to occur under Windows,
because Windows uses a different storage stack. It is also not proven absent
without measurement. Big Sur already provides the known-good storage behavior.

OpenCore Legacy Patcher can run newer macOS releases on this model, but the
Haswell/Kepler graphics stack requires post-install patches and update
maintenance. Test externally before considering any replacement of Big Sur.

## Implementation Phases

### 1. Preserve the baseline

- Maintain a current backup.
- Keep a tested recovery route.
- Export the installed MacPorts package list.
- Preserve at least 100 GB of free build/VM space.
- Do not repeat rejected writable Linux storage experiments.

### 2. Finish the native workstation

```bash
sudo /opt/local/bin/port selfupdate
sudo /opt/local/bin/port upgrade outdated
sudo /opt/local/bin/port install gh tree docker
npx @openai/codex@latest --version
```

Configure Git identity, credentials, editor, shell, and repository checkouts
without storing private credentials in this repository.

### 3. Package the compatibility lane

- Turn the proven Go patch into a local MacPorts overlay.
- Build an installable Go archive rather than rebuilding during normal work.
- Attempt Node 24 with MacPorts LLVM while retaining Node 22.
- Build Codex from Rust source only if its distributed native binary stops
  working.
- Record checksums, patches, tests, and rollback paths for every build.

### 4. Test real projects

Run each repository's own checks. Record whether it works natively, requires
only a remote Linux test stage, or needs the local Linux VM.

### 5. Establish the Linux engine

Prove one image build and one Compose stack against a remote engine. Add the
headless local engine only if offline operation is a real requirement.

### 6. Re-evaluate Big Sur only on evidence

Test a newer macOS externally when a required application or native runtime is
actually blocked. Do not migrate because of a warning alone.

## Source Register

| Source | Authority | Checked | Relevance |
| --- | --- | --- | --- |
| [MacPorts installation](https://www.macports.org/install.php) | Official | 2026-07-23 | Big Sur installer and legacy-host tooling |
| [MacPorts phases](https://guide.macports.org/chunked/reference.phases.html) | Official | 2026-07-24 | Verified source-build lifecycle |
| [MacPorts binary archives](https://guide.macports.org/chunked/using.binaries.html) | Official | 2026-07-24 | Source fallback when archives are unavailable |
| [MacPorts legacy-support](https://ports.macports.org/port/legacy-support/) | Official | 2026-07-24 | Compatibility wrappers for old macOS |
| [Rust Apple targets](https://doc.rust-lang.org/rustc/platform-support/apple-darwin.html) | Official | 2026-07-23 | Intel macOS host support |
| [Go minimum requirements](https://go.dev/wiki/MinimumRequirements) | Official | 2026-07-24 | Official host support boundaries |
| [Node 24 build requirements](https://github.com/nodejs/node/blob/v24.18.0/BUILDING.md) | Upstream | 2026-07-24 | Compiler, SDK, and C++ requirements |
| [Docker macOS client binaries](https://docs.docker.com/engine/install/binaries/#install-client-binaries-on-macos) | Official | 2026-07-24 | Native client versus Linux engine boundary |
| [QEMU system documentation](https://www.qemu.org/docs/master/system/) | Official | 2026-07-23 | Hypervisor.framework acceleration |
| [OCLP post-install patches](https://dortania.github.io/OpenCore-Legacy-Patcher/POST-INSTALL.html) | Upstream | 2026-07-23 | Haswell and Kepler patch requirements |

## Open Work

- Package Go 1.26.5 as a local MacPorts port.
- Attempt and validate an isolated native Node 24 build.
- Test QEMU/HVF on the exact Big Sur installation.
- Prove a remote Docker Engine workflow with a representative Compose stack.
- Build a per-repository native/Linux acceptance matrix.
- Recheck tool versions and upstream requirements before publishing major
  compatibility claims.
