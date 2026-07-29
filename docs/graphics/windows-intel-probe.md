# Windows Intel Enumeration Probe (Archived)

> This route is archived. The probe and result remain documented as useful
> hardware evidence, but do not use it to begin new Windows panel-routing,
> GMUX, or dGPU-power work. See the
> [archive decision](../archive/windows/README.md).

This procedure performs the smallest reversible Windows graphics experiment on
the tested `MacBookPro11,3`. It asks Apple firmware to leave Iris Pro visible,
then boots the existing Windows installation. It does not select Intel as the
panel owner or power off NVIDIA.

## Safety Contract

The prepared USB:

1. boots rEFInd only from removable FAT32 media;
2. calls Apple's Set OS protocol through `spoof_osx_version 10.9`;
3. scans the internal disk for the existing Windows EFI loader;
4. waits indefinitely for an explicit user selection;
5. stores rEFInd state on the USB rather than NVRAM where possible;
6. does not contain a GPU-preference writer or GMUX writer; and
7. does not install anything to the internal EFI partition.

Set OS is transient firmware-session state. A later direct Windows boot through
Apple's normal boot picker returns to the current firmware path.

## Physical Result

The probe passed on the tested machine on 2026-07-29. Windows changed from
NVIDIA-only enumeration to two healthy display devices:

- Intel Iris Pro 5200 loaded signed driver `10.18.10.3345`, service `igfx`,
  with PnP problem code 0 and no active display.
- NVIDIA GT 750M retained the active 2880x1800 panel, loaded signed driver
  `425.31`, and returned to P8 after settling.

A full shutdown, USB removal, and direct Windows boot restored NVIDIA-only
enumeration. No driver, internal disk, boot order, panel route, or GMUX state
was changed by this probe.

## Build

Install or extract a trusted rEFInd package, then point the builder at its
architecture-independent payload:

```bash
REFIND_ROOT=/usr/share/refind/refind \
  scripts/build-windows-igpu-probe.sh
```

The builder creates ignored output under:

```text
build/windows-igpu-probe/artifact/
```

It validates the x86-64 EFI application, creates a minimal fail-idle
configuration, records source metadata, and writes `SHA256SUMS`.

## Provision From Windows

The PowerShell writer never auto-selects a disk. Its first invocation is
read-only and prints an exact token:

```powershell
.\scripts\windows\write-igpu-probe-usb.ps1 `
  -DiskNumber 2 `
  -ArtifactRoot .\build\windows-igpu-probe\artifact
```

Review the model, bus type, size, and existing volume. Only then rerun from an
Administrator PowerShell with the exact printed token:

```powershell
.\scripts\windows\write-igpu-probe-usb.ps1 `
  -DiskNumber 2 `
  -ArtifactRoot .\build\windows-igpu-probe\artifact `
  -Confirm 'ERASE:2:EXACT_BYTE_SIZE:EXACT_MODEL'
```

The destructive path clears only the explicitly selected USB, creates a 1 GiB
GPT EFI System Partition, formats it FAT32 as `MBP_IGPU`, copies the artifact,
and verifies every SHA-256 digest from the USB.

## Provision From Linux

The Linux writer applies the same whole-disk identity, confirmation, source
checksum, and readback gates. Run its read-only preflight first:

```bash
scripts/write-windows-igpu-probe-usb.sh --device /dev/sdX
```

Then rerun it with `sudo` and the exact printed token. It accepts only a
removable USB whole disk from `/dev/sdb` through `/dev/sdz`, refuses mounted or
root-backed media, and verifies the FAT32 filesystem after unmounting it.

## User-Present Boot

1. Disconnect all external displays and storage other than the probe USB.
2. Shut Windows down fully.
3. Hold Option/Alt while powering on.
4. Select the external `EFI Boot` entry.
5. In rEFInd, select the existing Windows EFI loader. Do not select macOS for
   this measurement because Set OS applies to the entire current EFI session.
6. In Windows, inspect Device Manager for Intel Iris Pro 5200 and NVIDIA GT
   750M. Do not disable either device and do not install a driver yet.
7. Save only a sanitized device-state report.
8. Shut down. Remove the USB and boot Windows directly once to confirm the
   normal NVIDIA-only path still works.

Do not proceed to `gpu-power-prefs`, GMUX writes, driver replacement, or sleep
testing merely because Iris Pro appears. Those are separate authorization and
recovery gates.

The attempted Windows firmware-variable follow-up was later rejected because
Apple firmware accepted writes but denied runtime readback. See the
[dated source note](../source-notes/2026-07-29-windows-gmux-path.md) before
designing any panel-selection test.
