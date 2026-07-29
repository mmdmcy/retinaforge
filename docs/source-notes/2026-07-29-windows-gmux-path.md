# 2026-07-29 Windows GMUX And Intel-First Path

- Checked: `2026-07-29 Europe/Amsterdam`
- Scope: Windows 10 graphics state on the tested `MacBookPro11,3`, macOS-like
  Intel-first boot, Apple GMUX power control, and the smallest reversible test.
- Status: archived by product decision. The transient EFI exposure probe passed;
  panel selection and GMUX work were abandoned after firmware writes could not
  be read back. The explicit dedicated recovery path passed, and no GMUX command
  was issued.

## Exact Windows Baseline

The target currently exposes only the NVIDIA GeForce GT 750M to Windows. The
installed Boot Camp package identifies both relevant ACPI devices but binds
them to a null installation:

| Function | ACPI ID | Boot Camp binding |
| --- | --- | --- |
| Apple panel backlight | `ACPI\APP0002` | `NullDeviceInstall.NT` |
| Apple graphics mux | `ACPI\APP000B` | `NullDeviceInstall.NT` |

The inspected `AppleNull64.inf` contains no service for either device. It is a
placeholder, not a Windows GMUX or backlight driver. The GMUX device is present
without a PnP error and has an allocated I/O resource beginning at `0x700`.
This model uses the indexed pre-T2 Retina protocol, not the legacy direct-PIO
protocol used by older MacBook Pros and not the MMIO protocol used by T2 Macs.

The NVIDIA driver was updated from Boot Camp's `382.05` to NVIDIA's signed
`425.31` package. Its `nvaoi.inf` exactly matches
`PCI\VEN_10DE&DEV_0FE9&SUBSYS_0130106B`. The update passed native-resolution,
PnP, reboot, and idle-state checks. NVIDIA reports `P8`, its lowest available
performance state, but the GPU remains physically powered at about 53-60 C.
This rules out an accidentally forced high NVIDIA performance state as the
main idle-heat explanation.

## What macOS And Upstream Linux Establish

Apple firmware disables the Intel GPU on this model unless the boot path calls
Apple's Set OS EFI protocol. Upstream Linux now does this for
`MacBookPro11,3`. The call reports vendor `Apple Inc.` and version
`Mac OS X 10.9`; the version string itself is not believed to be significant.

The Apple EFI variable
`gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9` selects the initial
panel owner. Its fifth byte is `1` for integrated graphics and `0` for
discrete graphics. Set OS and the preference have different jobs:

1. Set OS prevents firmware from hiding the Iris Pro.
2. `gpu-power-prefs` asks EFI to allocate the boot framebuffer and route the
   panel for the selected GPU.
3. The active display driver initializes the selected GPU and Retina eDP link.
4. The inactive NVIDIA graphics and HDA functions must be quiesced.
5. GMUX receives the discrete-power command and sequences the GPU core, VRAM,
   and PCIe rails.

For this indexed GMUX, the host-visible discrete-power commands are:

```text
power on:  write 1, then 3 to logical register 0x50
power off: write 1, then 0 to logical register 0x50
```

GMUX firmware owns the internal regulator order and timing. Completion appears
as bit 2 in interrupt status register `0x16`. Linux waits up to 200 ms for the
completion notification. Linux also restores cached display routing and
reasserts the off state after resume because GMUX does not preserve all state
across suspend.

Retina eDP is a material constraint. The inactive GPU cannot independently
train the panel through AUX; coordinated handoff requires pre-calibrated link
parameters and cooperation from both display drivers. Thunderbolt/DisplayPort
main links are physically tied to the discrete side on this generation, so an
Intel-only mode sacrifices those external outputs.

## Why The First Probe Is Smaller

The first test must answer only one question: does calling Set OS immediately
before Windows boot make Iris Pro enumerate on this exact firmware?

The probe uses a removable FAT32 rEFInd installation with:

```text
spoof_osx_version 10.9
```

It does not write `gpu-power-prefs`, access GMUX registers, install a driver,
modify the internal EFI partition, or change the default boot order. The user
boots the USB through Apple's Option picker, selects the normal Windows EFI
loader from rEFInd, and inspects display devices. A subsequent direct boot from
Apple's picker returns to the existing NVIDIA-only path.

If Iris Pro does not enumerate, stop and capture only the EFI and Windows PnP
state. If it does enumerate, preserve that result before attempting panel
selection.

## Stage 1 Physical Result

The user-present removable-media probe passed on 2026-07-29. Booting Windows
through rEFInd with `spoof_osx_version 10.9` changed display enumeration from
NVIDIA-only to both GPUs:

| Device | PnP result | Driver | Display state |
| --- | --- | --- | --- |
| Intel Iris Pro 5200, `8086:0d26` | present, started, problem code 0 | signed Intel `10.18.10.3345`, service `igfx` | no active resolution |
| NVIDIA GT 750M, `10de:0fe9` | present, started, problem code 0 | signed NVIDIA `425.31` | active 2880x1800 panel |

The Apple GMUX and panel-backlight ACPI devices remained present with problem
code 0 and their existing null Boot Camp bindings. After settling, NVIDIA
returned to P8 at 56 C. No GPU preference, GMUX register, internal disk, driver,
or boot-order change was made. A full shutdown, USB removal, and direct Apple
boot restored NVIDIA-only enumeration, proving the Intel exposure was transient.

This establishes that Set OS is sufficient to expose and start the existing
Intel Windows driver on this exact firmware. It does not establish Intel panel
ownership or discrete rail-off.

## Stage 2 Windows Runtime Result

The next user-present gate attempted to inspect and update `gpu-power-prefs`
through Windows firmware-variable APIs. The tool required exact
`Apple Inc. MacBookPro11,3` SMBIOS identity, UEFI mode, an elevated token with
`SeSystemEnvironmentPrivilege` verified as enabled, exact confirmation tokens,
an immutable backup, and post-write readback. BitLocker was fully disabled.

The initial firmware read returned Windows error 5. Microsoft documents that
UEFI may return a firmware-specific no-access error when a vendor namespace is
absent, and the machine's known direct-boot behavior was consistent with an
absent preference. The backup therefore recorded the original state as absent.

Windows then reported success from `SetFirmwareEnvironmentVariableEx` for the
integrated payload `01000000`, but Apple firmware continued to deny runtime
readback. The tool correctly rejected the operation as unverifiable and no
Intel-panel boot was attempted. Deleting the variable through the same Windows
API failed with error 87. An explicit dedicated payload `00000000` was then
accepted as the recovery value, although it was subject to the same readback
restriction.

A full shutdown, USB removal, and direct Apple boot behaviorally verified the
recovery state: only NVIDIA enumerated, PnP problem code remained 0, the panel
ran at 2880x1800, and NVIDIA settled to P8 at 56 C. The current machine may have
an explicit dedicated preference rather than the original absent variable;
Windows cannot distinguish those states, but both select the known-good
discrete boot path.

This Windows runtime mechanism is rejected for further mutation because it
cannot satisfy readback. A future panel-selection test must inspect and update
the variable from EFI or macOS, verify the exact result there, retain an NVRAM
reset recovery, and remain user-present. No reusable Windows preference writer
is retained in the repository.

## Path Assessment At Pause

Windows has one strong positive result: Set OS exposes Iris Pro and its existing
signed driver starts cleanly. Reaching macOS-like thermals still requires two
unproven steps: routing the Retina panel to Intel and implementing guarded GMUX
power-off plus resume handling without support from Apple's Windows drivers.

Linux is the easier environment for graphics control because current upstream
has Apple Set OS, `i915`, `apple-gmux`, VGA switcheroo, and kernel-level suspend
coordination. That does not solve this machine's internal-storage problem:
legacy INTx still shows roughly 1.1-second durable-flush tails, while MSI plus
NCQ writes caused timeouts and hard SATA resets. An external USB SSD can be a
non-production graphics lab medium, but it is not the selected route. The active
goal is native Linux on the original internal SSD, which remains blocked on the
storage mechanism rather than a deliberately accepted durability compromise.

## Archive Decision

On 2026-07-29, the Windows route was closed as an active engineering track.
Windows remains a working recovery and compatibility OS, but reproducing Big
Sur behavior would require verified Intel panel routing plus custom Windows
coordination of display drivers, backlight, NVIDIA graphics and HDA, GMUX rail
sequencing, sleep, and recovery. That is not an acceptable use of further work
on this machine. Retain this note as hardware evidence only; pursue native
Linux through the separate
[`linux-native-roadmap.md`](../linux-native-roadmap.md).

## Historical Staged Implementation

The stages below record the analysis that led to the archive decision. They are
not an active Windows work plan.

### Stage 1: transient Intel enumeration

- Boot rEFInd only from removable media.
- Call Set OS through rEFInd's maintained implementation.
- Leave GPU preference and GMUX untouched.
- Boot Windows and record both display devices, driver state, and temperatures.
- Return through a normal shutdown and direct Apple boot.

### Stage 2: one-boot Intel panel selection

- Back up and verify the complete original `gpu-power-prefs` value.
- Ensure the supported Haswell Iris Pro Windows driver is staged.
- Keep all external displays disconnected.
- Select Intel only after Stage 1 proves that it starts in Windows.
- Keep a discrete boot entry and Apple NVRAM-reset recovery available.
- Test a cold boot before brightness or sleep.

Stage 2 may produce a black image or a lit image without backlight. It remains
a user-present experiment. It is paused; the rejected Windows runtime writer
must not be reused.

### Stage 3: read-only Windows GMUX driver

A clean-room KMDF driver can replace the null binding only for
`ACPI\APP000B` on `MacBookPro11,3`. Its first version should:

- claim the translated I/O resource and require base `0x700` on this target;
- validate the indexed handshake and read the GMUX version;
- serialize all indexed transactions and fail on every timeout;
- expose read-only panel, external-route, brightness, interrupt, and power
  diagnostics;
- register ACPI notifications without issuing power or routing commands;
- provide no arbitrary port-access IOCTL.

Linux `apple-gmux.c` is GPL-2.0-only. It is an authoritative hardware reference,
not code to paste into a differently licensed Windows driver. The protocol can
be reimplemented cleanly from documented hardware facts and observed behavior.

### Stage 4: guarded cold-boot NVIDIA power-off

The first mutating implementation should support only an already-selected
Intel boot, not live switching. It must refuse power-off unless:

- SMBIOS is exactly `MacBookPro11,3`;
- Iris Pro is present, started, and owns the internal panel;
- NVIDIA graphics and HDA functions are stopped;
- no external display is connected;
- GMUX already reports the panel on Intel;
- ACPI power-completion notification is working;
- the dedicated-GPU recovery boot remains available.

Initially disable S3 and use shutdown or hibernation. Resume restoration is a
separate gate. Full dynamic switching would require cooperation from the Intel
and NVIDIA Windows display miniports and is not the first deliverable.

## Source Register

- [Linux `apple-gmux.c`](https://github.com/torvalds/linux/blob/master/drivers/platform/x86/apple-gmux.c)
- [Linux VGA Switcheroo documentation](https://docs.kernel.org/gpu/vga-switcheroo.html)
- [Linux Set OS commit `71e49eccdca6`](https://github.com/torvalds/linux/commit/71e49eccdca6328eecc335ed8f5557bd0ed70fc6)
- [rEFInd configuration documentation](https://www.rodsbooks.com/refind/configfile.html)
- [`0xbb/apple_set_os.efi`](https://github.com/0xbb/apple_set_os.efi)
- [`0xbb/gpu-switch`](https://github.com/0xbb/gpu-switch)
- [Apple IOGraphics source](https://github.com/apple-oss-distributions/IOGraphics)
- [Microsoft D3cold documentation](https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/supporting-d3cold-in-a-driver)

## Stop Conditions

- Never issue GMUX power commands while NVIDIA owns the panel.
- Never infer rail-off from a disabled device or absent driver.
- Stop on a black panel, lost backlight, PnP error, display-driver reset,
  interrupt storm, failed GMUX transaction, or changed external-display state.
- Do not combine this graphics test with an AHCI kernel experiment.
- Do not perform first panel, power, NVRAM, sleep, or reboot tests unattended.
