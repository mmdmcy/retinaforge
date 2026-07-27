# Modern Development On MacBookPro11,3

Making one specific Late-2013 15-inch Retina MacBook Pro configuration useful
as a modern, terminal-first development workstation without pretending it is
officially supported hardware.

## Exact Scope

| Component | Tested target |
| --- | --- |
| Apple model identifier | `MacBookPro11,3` |
| Product | 15-inch Retina MacBook Pro, Late 2013 |
| CPU | Intel Core i7-4960HQ |
| Memory | 16 GB DDR3L |
| Graphics | Intel Iris Pro and NVIDIA GeForce GT 750M |
| Internal storage | 1 TB `APPLE SSD SM1024F` |
| Storage controller | Apple/Samsung AHCI, PCI ID `144d:1600` |
| Host operating system | macOS Big Sur `11.7.11` |

This repository does not claim that its patches, Linux findings, or setup
instructions apply to every MacBook Pro sold in 2013. Other 13-inch and
15-inch models can use different model identifiers, CPUs, graphics, storage
devices, controller behavior, and firmware. Treat broader compatibility as
unverified until it is tested and recorded.

The working strategy is native-first:

- keep macOS Big Sur as the stable host;
- install maintained native packages through MacPorts;
- compile compatibility builds when an upstream support cutoff is newer than
  the operating-system APIs the software actually needs;
- use Linux only where a Linux kernel is genuinely required, such as Docker
  Engine, kernel work, or deployment-parity tests.

This is a tested project, not only a proposal. On the physical target described
above, current Git, Node 22, Python 3.13, Rust 1.97, Go 1.24, Neovim, and the
Codex CLI ran natively. Go 1.26.5 was then built from official source with a
small compatibility patch and passed targeted runtime, TLS, certificate, HTTP,
and linker tests on Big Sur 11.7.11.

## Current Result

| Area | Result |
| --- | --- |
| Native terminal development | Working |
| Current Codex CLI | Working natively |
| Rust, Python, C/C++, Git | Working natively |
| Node.js | Node 22 working; Node 24 compatibility work remains |
| Go | 1.24 packaged; patched 1.26.5 built and tested |
| Docker CLI and Compose | Native clients are possible |
| Docker Engine | Requires a remote Linux host or a small Linux VM |
| Bare-metal Linux | Paused because of controller-specific write-latency behavior |
| Windows 10/11 | Not the preferred modernization route |

## Start Here

- [Modern workstation plan](docs/modern-workstation-plan.md)
- [Native-first architecture](docs/architecture.md)
- [Go 1.26.5 Big Sur validation](docs/go-1.26.5-validation.md)
- [Current handoff](docs/handoff.md)
- [Historical Big Sur recovery record](docs/history/2026-07-14-big-sur-recovery-and-linux-roadmap.md)
- [Go compatibility patch](patches/go-1.26.5-big-sur.patch)

For a conservative native baseline after installing the official Big Sur
MacPorts package:

```bash
sudo ./scripts/bootstrap-big-sur-dev.sh
```

To reproduce the patched Go build on an Intel Mac running Big Sur:

```bash
./scripts/build-go-1.26.5-big-sur.sh
```

The build script creates a fresh temporary workspace and deliberately leaves
the result in place for inspection. It does not replace the installed Go
toolchain.

## Related Linux Storage Work

The controller investigation lives in this same repository under the Linux
storage workbench sections, scripts, patches, and `docs/` tree.

It has not produced a confirmed safe Linux fix and must not be presented as a
general Apple AHCI solution. It documents why installing Linux directly on the
tested machine is not currently the default recommendation. The native macOS
workstation described here does not depend on solving that storage issue.

## Safety

This project targets unsupported legacy hardware. Back up the machine, keep a
known-good recovery route, and test compatibility builds alongside stable
toolchains. Do not repeat destructive disk experiments or install experimental
kernel changes merely to reproduce the research.

## License

The original project material under `macos/` is available under the
[BSD 3-Clause License](LICENSE). The Go patch applies to source distributed by
the Go project under its own BSD-style license. Linux storage/kernel material
at the repository root remains GPL-2.0.
