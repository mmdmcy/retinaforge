# 2026-07-15 `macbookpro11-3-cachyos` Review

- Checked: `2026-07-15 16:30 Europe/Amsterdam`
- Researcher: `Codex`
- Scope: complete repository audit, upstream validation, applicability to this
  workbench, and repository naming implications.
- Status: useful model-specific graphics evidence; not safe as a turnkey
  installer and unrelated to the confirmed internal-SSD durability problem.

## Questions

- Does the repository address the same MacBook and graphics hardware?
- Which parts are supported by upstream Linux rather than anecdote?
- Can its Intel-only design help this project without repeating the earlier
  dangerous live GPU-switching attempt?
- Which scripts or claims must not be copied directly?
- What should this workbench be called now that its scope includes storage,
  EFI boot, graphics, GMUX, power, and upstream contributions?

## Repository Snapshot

Repository: [`joaodriessen/macbookpro11-3-cachyos`](https://github.com/joaodriessen/macbookpro11-3-cachyos)

State observed on 2026-07-15:

- public, unarchived repository;
- created and first pushed on 2026-07-02;
- one branch (`main`), one commit, no tags or releases;
- no issues or pull requests;
- 25 files and approximately 1,283 lines;
- one star, no forks at inspection time;
- all content arrived in commit
  [`6d17b468`](https://github.com/joaodriessen/macbookpro11-3-cachyos/commit/6d17b4681eb58dd1586f22c0bc88d551059d059b).

This is best understood as a carefully written single-machine migration diary,
not a mature driver, maintained package, tested installer, or evidence that
CachyOS generally solves `MacBookPro11,3` hardware.

## Claimed Result

The repository describes moving a `MacBookPro11,3` from the NVIDIA GT 750M to
the Intel Iris Pro 5200 under CachyOS, Limine, KDE Plasma, and a 7.x CachyOS
kernel. Its intended end state is:

- boot through a Unified Kernel Image (UKI) as an EFI application;
- let the upstream Linux EFI stub call Apple's `set_os` protocol so firmware
  leaves the normally hidden iGPU enabled;
- set Apple's `gpu-power-prefs` EFI variable to select the iGPU at next boot;
- prevent proprietary NVIDIA and Nouveau modules from loading;
- use Intel i915/Mesa for the desktop and the legacy `i965` VA-API driver;
- accept losing external-display output;
- retain SSH and a separate boot entry for recovery.

The high-level boot and mux mechanism is credible and directly relevant to our
same model. The storage problem is not discussed, and the repository contains
no SSD model, controller latency measurements, `fsync()` traces, or evidence
that the author's internal storage matches `APPLE SSD SM1024F / UXM6JA1Q`.

## What Upstream Evidence Confirms

### Linux EFI-stub `apple_set_os`

Upstream Linux commit
[`71e49eccdca6`](https://github.com/torvalds/linux/commit/71e49eccdca6328eecc335ed8f5557bd0ed70fc6)
added an EFI-stub call to Apple's `set_os` protocol for an explicit DMI list
that includes `MacBookPro11,3`. The commit explains that Apple firmware disables
the iGPU unless the boot path reports macOS. This validates the repository's
central mechanism.

The patch was committed on 2024-06-30. Therefore Linux 6.8 predates it. A later
upstream fix,
[`4f90742d4a09`](https://github.com/torvalds/linux/commit/4f90742d4a09a8253861b0d5fd0984e3cd399c9b),
added a fallback SMBIOS lookup in 2025 because some Apple EFI implementations
otherwise prevented `apple_set_os()` from identifying the machine. A future
test should use a kernel containing both changes or backport both deliberately.

The EFI-stub function runs only when the kernel's EFI entry path is actually
executed. Limine supports separate `linux` and `efi` protocols in its
[official configuration](https://github.com/Limine-Bootloader/Limine/blob/v11.x/CONFIG.md).
The repository's UKI chainload design is therefore a plausible way to ensure
the EFI stub executes. This does not prove that every bootloader's native Linux
path behaves identically; our future design should verify the chosen boot path
instead of copying Limine-specific assumptions.

### GMUX and `gpu-power-prefs`

The kernel's
[VGA Switcheroo documentation](https://docs.kernel.org/gpu/vga-switcheroo.html)
describes Apple GMUX as the hardware mux and power handler for dual-GPU
MacBooks. It documents the same
`gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9` variable and states that
its fifth byte selects integrated (`1`) or discrete (`0`) graphics at boot.
It also confirms that newer MacBook generations route external outputs through
the discrete GPU and that GMUX—not merely module blacklisting—performs the
actual discrete-GPU power cut.

The older [`0xbb/gpu-switch`](https://github.com/0xbb/gpu-switch) project lists
`MacBookPro11,3` as tested hardware and documents the need for `apple_set_os`
before the Intel GPU can be used. This independently supports the EFI-variable
and hidden-iGPU model.

The repository's concern about a complete efivarfs payload is grounded in the
upstream [`efivarfs_file_write()`](https://github.com/torvalds/linux/blob/master/fs/efivarfs/file.c)
interface: one write is parsed as four attribute bytes followed by variable
data. An incomplete first write can therefore create a malformed data-less
value. Its eight-byte write and size check are directionally safer than blindly
copying an old shell redirection.

### NVIDIA and Wayland

NVIDIA's 470 series supports the Mac GT 750M PCI IDs `0fe4` and `0fe9`; current
NVIDIA documentation classifies 470 as a legacy branch. NVIDIA added GBM support
in the later
[495.44 release](https://www.nvidia.com/download/driverResults.aspx/181274/en-us/1000/),
which does not provide a supported upgrade path for this Kepler mobile GPU.
The repository is therefore substantially correct that proprietary 470 lacks
the newer GBM path expected by current Wayland stacks.

The exact `plasmalogin`/SDDM crash, PowerMizer temperature, Parsec stall, and
Steam Link color inversion are machine observations without attached logs,
upstream bug links, or before/after datasets. Treat them as useful leads, not
general facts about every `MacBookPro11,3`.

### Intel VA-API

Intel's modern `iHD` media driver starts with newer hardware generations;
Intel maintainers direct older hardware to the legacy
[`intel-vaapi-driver`](https://github.com/intel/intel-vaapi-driver). Pinning
`LIBVA_DRIVER_NAME=i965` for Haswell is plausible, but it should be validated
with `vainfo` and an actual decode workload rather than assumed globally for
every application.

## Complete Code-Audit Findings

### Strong ideas worth carrying forward

1. Use a separate UKI/EFI boot entry to test `apple_set_os` without changing the
   normal boot entry.
2. Wake the iGPU before selecting it; changing only the mux preference can leave
   a black panel if firmware disabled the Intel device.
3. Establish and verify remote recovery before touching NVRAM, GMUX, initramfs,
   display managers, or GPU drivers.
4. Use explicit preflight checks, one rebooted state change at a time, and
   read-only verification after every boot.
5. Keep graphics work independent from storage experiments so one subsystem
   cannot disguise the other's result.
6. Prefer the upstream EFI-stub implementation over an unmaintained third-party
   `apple_set_os.efi` shim.
7. Accept and document that Intel-only operation sacrifices external displays
   on this hardware.

### Reasons the scripts must not be run verbatim

1. `build-uki-igpu-test.sh`, `nvidia-off.sh`, and
   `revert-nvidia-off.sh` contain the author's kernel version and root-filesystem
   UUID. On another installation they can build an unbootable UKI. The README
   warns about this, but the scripts still execute without requiring replacement
   placeholders.
2. `nvidia-off.sh` replaces the entire `MODULES=(...)` line with
   `MODULES=(i915)`. That can discard installation-specific early-boot modules
   and is unsafe as a general transformation.
3. `enable-ssh-recovery.sh` enables password-accessible SSH and opens the
   firewall service without restricting source networks or first requiring
   key-based authentication. It is a recovery convenience with a security
   trade-off, not a safe universal step.
4. `scripts/diagnostics/` is described as read-only, but
   `dgpu-poweroff-probe.sh` writes PCI runtime-power state, loads `acpi_call`,
   and invokes guessed ACPI methods. On different hardware, such calls can have
   real power consequences. This script is not read-only.
5. `mux-to-nvidia.sh` intends to fall back to an explicit discrete-value write
   if variable deletion fails, but `set -e` causes a failing `rm` to exit before
   the fallback branch can execute.
6. `enable-uki-persist.sh` suppresses `limine-update` failure with `|| true` and
   lacks a matching persistent-mode revert script. The test-UKI revert removes
   only the standalone test entry.
7. Several other mutating scripts also lack the paired revert claimed by the
   README, including the SSH, display-manager, PowerMizer, persistent-UKI, and
   VA-API changes.
8. Installing `gpu-switch.upstream` is questionable after the same repository
   says its redirection produced a malformed variable. The install script's
   integrity check only searches for the EFI GUID; it does not verify a pinned
   upstream commit or hash.
9. The vendored file is described as "unmodified," but it changes comments,
   copyright text, and whitespace compared with current upstream. Its functional
   body is effectively the same, but the provenance statement is not literal.
10. No CI, shell linting, automated fixtures, releases, or second-machine test
    evidence exists. Bash parsing succeeds, but that is much weaker than safe
    hardware validation.

### Important contradiction about dGPU power

The README's opening says the GT 750M is "fully powered down," and
`nvidia-off.sh` says it powers the GPU down "for good." However:

- that script only edits initramfs/module policy and rebuilds a UKI;
- it never calls Apple GMUX or VGA Switcheroo to cut the power rails;
- the repository's own D3cold section says the driverless GT 750M remains
  electrically powered and that full power-off was abandoned;
- its own diagnostic script says blacklisting alone leaves the card powered.

The defensible result is **Intel-only rendering with NVIDIA drivers absent**,
not a proven fully powered-off dGPU. The observed thermal improvement may still
be real because the proprietary driver and forced clocks are gone, but the
power-state claim requires direct GMUX/VGA Switcheroo evidence.

## Applicability To This Workbench

| Area | Applicability | Decision |
| --- | --- | --- |
| Exact Mac model and dual-GPU layout | High | Reuse the hardware model and upstream references. |
| EFI-stub `apple_set_os` | High | Add as the preferred future iGPU wake mechanism. |
| UKI test entry | High conceptually | Implement distro-neutral tooling; do not copy hardcoded CachyOS/Limine scripts. |
| `gpu-power-prefs` mux selection | High but risky | Reimplement with captured original value, atomic write, verification, and tested recovery. |
| Intel-only desktop | High | Strong candidate for stable thermals after storage is solved or bypassed. |
| NVIDIA 470/Wayland diagnosis | Medium-high | Consistent with our prior Nouveau/NVIDIA instability; reproduce independently. |
| Full dGPU power-off | Not demonstrated | Keep as a separate GMUX/VGA Switcheroo research problem. |
| SSD latency | None | Repository supplies no storage evidence and does not alter AHCI/libata. |
| CachyOS as a distro fix | None | Its graphics mechanism is boot-path-specific, not proof that CachyOS fixes storage. |

This source strengthens the case that our earlier heat and Xorg instability had
a graphics component separate from the measured SSD stalls. It also supplies a
safer graphics architecture than live `vgaswitcheroo` switching: prepare an
isolated EFI/UKI path, boot into an already-selected iGPU state, verify, and only
then make anything persistent.

It does not change the storage decision. Any future Linux test still needs the
macOS `fsync()`/`F_FULLFSYNC` discriminator and a storage path that does not make
the entire desktop block for seconds.

## Recommended Graphics Experiment For This Project

After the storage decision is resolved:

1. Use a current upstream kernel containing commits `71e49eccdca6` and
   `4f90742d4a09`.
2. Build on another machine or in a VM.
3. Generate a UKI from discovered values; reject literal example UUIDs and
   kernel versions.
4. Add a one-time EFI chainload entry while keeping macOS and a known-good boot
   route.
5. Confirm the iGPU appears before changing mux preference.
6. Back up the original EFI variable and verify exact byte count and content.
7. Select Intel for one boot with SSH key-based recovery already tested.
8. Verify i915, panel ownership, suspend/resume, brightness, video decode,
   temperatures, fan behavior, and repeated cold boots.
9. Disable NVIDIA/Nouveau only after the Intel path passes.
10. Measure the dGPU's real PCI and GMUX power state; do not label it powered
    off merely because no module is loaded.
11. Decide explicitly whether loss of HDMI/Thunderbolt display output is
    acceptable.

## Repository Naming Decision

The initial review recommended one umbrella repository named
`macbookpro11-3-linux-workbench`. That recommendation was superseded after
separating the two independent engineering problems.

Current proposed repositories:

- `macbookpro11-3-ahci-latency` for storage evidence, reproducers, block-layer
  prototypes, AHCI/libata patches, and storage upstream work;
- `macbookpro11-3-linux-graphics` for EFI/iGPU boot, GMUX, Nouveau/NVIDIA,
  displays, power, suspend, and graphics upstream work.

The exact DMI model remains useful for discovery, while separate repositories
prevent storage and graphics hypotheses, test matrices, maintainers, and patch
series from becoming entangled. An umbrella repository can be added later if
both projects produce mature artifacts that need a shared landing page.

Do not rename the local directory or GitHub repository until the current dirty
worktree is committed safely and all internal links, remote URLs, repository
description, and publication notes can be updated together.

## Source Register

| Source | Authority | Checked | Status | Notes |
| --- | --- | --- | --- | --- |
| [`macbookpro11-3-cachyos` pinned commit](https://github.com/joaodriessen/macbookpro11-3-cachyos/commit/6d17b4681eb58dd1586f22c0bc88d551059d059b) | Primary project source | 2026-07-15 | One-commit snapshot | Complete repository state reviewed locally. |
| [Project README at pinned commit](https://github.com/joaodriessen/macbookpro11-3-cachyos/blob/6d17b4681eb58dd1586f22c0bc88d551059d059b/README.md) | Primary project source | 2026-07-15 | Current at inspection | Architecture, trade-offs, and claims. |
| [Linux `apple_set_os` commit](https://github.com/torvalds/linux/commit/71e49eccdca6328eecc335ed8f5557bd0ed70fc6) | Upstream Linux | 2026-07-15 | Merged | Explicit `MacBookPro11,3` DMI match and EFI-stub call. |
| [Linux SMBIOS fallback commit](https://github.com/torvalds/linux/commit/4f90742d4a09a8253861b0d5fd0984e3cd399c9b) | Upstream Linux | 2026-07-15 | Merged | Makes Apple product lookup work on EFI lacking the SMBIOS protocol. |
| [Linux VGA Switcheroo/GMUX documentation](https://docs.kernel.org/gpu/vga-switcheroo.html) | Upstream Linux documentation | 2026-07-15 | Current | Confirms GMUX power role, EFI variable, and output-routing limits. |
| [Limine configuration](https://github.com/Limine-Bootloader/Limine/blob/v11.x/CONFIG.md) | Upstream bootloader documentation | 2026-07-15 | Versioned | Distinguishes native Linux and EFI chainload protocols. |
| [`0xbb/gpu-switch`](https://github.com/0xbb/gpu-switch) | Original community project | 2026-07-15 | Old but directly relevant | Documents `MacBookPro11,3`, EFI variable, and `apple_set_os` requirement. |
| [Linux efivarfs write implementation](https://github.com/torvalds/linux/blob/master/fs/efivarfs/file.c) | Upstream Linux source | 2026-07-15 | Current; recheck by commit before implementation | Parses each write as attributes plus data. |
| [NVIDIA 495.44 release](https://www.nvidia.com/download/driverResults.aspx/181274/en-us/1000/) | NVIDIA | 2026-07-15 | Historical release record | Identifies 495 as the release adding GBM. |
| [NVIDIA 470 supported chips](https://download.nvidia.com/XFree86/Linux-x86_64/470.199.02/README/supportedchips.html) | NVIDIA | 2026-07-15 | Historical legacy-driver record | Includes GT 750M family support. |
| [Intel legacy VA-API driver](https://github.com/intel/intel-vaapi-driver) | Intel | 2026-07-15 | Maintained source archive | Relevant media path for pre-Broadwell Intel graphics. |

## Recheck Triggers

- The reviewed repository gains commits, issues, releases, measurements, or
  support for another bootloader/distro.
- Upstream Linux changes the `apple_set_os` DMI list or GMUX behavior.
- A current kernel demonstrates automatic safe dGPU power-off without Nouveau.
- This project begins an actual Intel-only boot test.
- The local/GitHub repository is about to be renamed.

## Open Questions

- Does Big Sur `F_FULLFSYNC` reproduce the 0.8-second strict durability delay?
- Does a current EFI-stub kernel expose the iGPU reliably on our exact firmware
  without the 2025 SMBIOS fallback being backported?
- Can Nouveau register safely enough for GMUX to cut dGPU power after the panel
  is already on Intel, without recreating the prior Xorg crash path?
- Can external outputs be supported through a deliberately loaded, non-display
  dGPU path without destabilizing the Intel-driven desktop?
- What exact before/after idle power, temperature, and fan measurements does the
  reviewed repository's author observe?
