# Archived Windows Graphics Route

Status: archived by product decision on 2026-07-29. This material is retained
because it produced useful hardware facts, but no further Windows GMUX, panel
routing, firmware-preference, driver, sleep, or NVIDIA power work is planned.

## What It Established

The removable rEFInd probe called Apple's Set OS protocol immediately before
Windows boot. On the tested `MacBookPro11,3`, this changed Windows from
NVIDIA-only display enumeration to two healthy GPUs:

- Intel Iris Pro 5200 (`8086:0d26`) started with signed Intel driver
  `10.18.10.3345` and service `igfx`.
- NVIDIA GT 750M (`10de:0fe9`) retained the active 2880x1800 internal panel,
  then settled to P8 at 56 C with signed NVIDIA driver `425.31`.

A full shutdown, USB removal, and direct Apple Windows boot restored the
NVIDIA-only state. This is strong evidence that Set OS exposes Intel but does
not itself select the panel or power off NVIDIA.

Windows firmware-variable APIs were also evaluated. They could be elevated and
report success for preference writes, but Apple firmware denied runtime readback
of the vendor variable. The method was rejected because it could not verify a
panel-selection request before reboot. A subsequent explicit dedicated request
followed by a direct boot recovered the known-good NVIDIA-only path. No GMUX
power command was issued.

## Why It Is Archived

Reproducing Big Sur behavior under Windows would still require verified panel
routing, backlight and sleep behavior, explicit coordination of NVIDIA graphics
and HDA, guarded GMUX rail sequencing, and a recovery-safe driver path. That is
a custom Windows kernel-driver project with no maintained model-specific
solution. It is not the chosen route for this machine.

## Retained Records

- [Complete Windows GMUX and Intel-first source note](../../source-notes/2026-07-29-windows-gmux-path.md)
- [Transient Intel-enumeration probe procedure and result](../../graphics/windows-intel-probe.md)
- [Probe builder](../../../scripts/build-windows-igpu-probe.sh)
- [Guarded Windows USB writer](../../../scripts/windows/write-igpu-probe-usb.ps1)

The last validated USB artifact remains an Intel-enumeration probe only. Do not
use it as a panel-selection, GMUX, or dGPU-power tool.
