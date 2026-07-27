# Native-First Architecture

## Runtime Shape

The Mac remains the interactive workstation. Editing, Git, terminal agents,
language servers, and ordinary builds run directly on macOS.

```text
macOS Big Sur
├── MacPorts stable toolchains
├── isolated source-built compatibility toolchains
├── editor, Git, Codex, Docker CLI and Compose
└── Linux boundary
    ├── preferred: remote Docker/build host
    └── optional: small headless QEMU/HVF VM
```

The Linux boundary is a service, not the everyday desktop or development
shell.

## Core Boundaries

### Stable native lane

MacPorts owns ordinary packages under `/opt/local`. Its Portfiles describe how
to fetch, verify, patch, build, stage, and activate software. Binary archives
are an optimization; when one is unavailable, MacPorts builds the same port
from source.

This is how MacPorts can continue supporting old macOS releases: maintainers
can pin compatible dependencies, carry small patches, select an appropriate
compiler, and use `legacy-support` wrappers for APIs missing from older
systems.

### Compatibility lane

Unsupported-version experiments must remain isolated from the stable lane.
Each build records:

- exact upstream version and source checksum;
- compiler and bootstrap toolchain;
- deployment target and SDK;
- patch set;
- targeted runtime tests and at least one real project test;
- rollback or side-by-side installation path.

An upstream support policy is evidence of what the project tests and promises.
It is not always proof that the binary cannot run on an older system. The Go
1.26.5 experiment demonstrates the difference. Compatibility is accepted only
after testing, not assumed from a successful compile.

### Linux boundary

Docker Engine is a Linux daemon and requires a Linux kernel. The Docker CLI,
Compose client, source tree, editor, and terminal workflow can remain native
on macOS while talking to:

1. a trusted remote Linux engine over SSH; or
2. a small local headless Linux VM accelerated by Hypervisor.framework.

Bare-metal Linux is a separate hardware research route and is not required for
the workstation.

## Verification

Every native runtime must pass its own version check and a representative
repository test:

```bash
git --version
node --version
python3 --version
rustc --version
cargo --version
go version
codex --version

cargo check --workspace
go test ./...
npm ci && npm test
python3 -m pytest
```

Do not weaken a repository's declared requirements merely to make it pass on
Big Sur. Test a compatibility build first, then move only the incompatible
build or test stage across the Linux boundary.
