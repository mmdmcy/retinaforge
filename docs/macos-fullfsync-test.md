# macOS `fsync` / `F_FULLFSYNC` Test

This is the decisive experiment on the currently installed Big Sur `11.7.11`
reference system. Run it on the internal Apple SSD, not an external installer,
USB volume, network share, or RAM disk.

## Build

Copy `tools/macos-fullfsync-probe.c` to the Mac, open Terminal, and run:

```sh
xcode-select --install
clang -O2 -Wall -Wextra macos-fullfsync-probe.c -o macos-fullfsync-probe
```

If Command Line Tools cannot be installed immediately, the same source can be
compiled on another compatible Intel Mac and copied over.

## Run

From the macOS user account's home directory:

```sh
./macos-fullfsync-probe "$HOME" 12 1024 | tee macos-fullfsync-results.txt
```

The probe writes two temporary 12 MiB files in 1 MiB steps. It removes each
file after its mode completes. It prints each write/sync duration and summary
statistics for ordinary `fsync()` and strict `F_FULLFSYNC`.

Also capture:

```sh
system_profiler SPHardwareDataType SPNVMeDataType SPSerialATADataType
ioreg -l -p IODeviceTree > ioreg-device-tree.txt
ioreg -l -p IOService > ioreg-service.txt
```

Review and sanitize serial numbers before committing any output.

## Interpretation

- Fast `fsync()`, slow `F_FULLFSYNC`: macOS obtains responsiveness through its
  weaker ordinary-sync contract; no hidden fast strict command is demonstrated.
- Fast `fsync()` and fast `F_FULLFSYNC`: capture controller state and resume
  Linux driver work because Apple has a behavior missing from the static
  analysis.
- Both slow: investigate whether the test is on the internal SSD and whether
  another workload is already saturating storage before drawing conclusions.

## Initial Result

On 2026-07-17, the probe ran on the internal APFS Data volume under Big Sur
`11.7.11` with 12 one-mebibyte samples in each mode:

| Mode | Mean sync | Median sync | P95 sync | Maximum sync |
| --- | ---: | ---: | ---: | ---: |
| ordinary `fsync()` | 1.134 ms | 1.094 ms | 1.560 ms | 1.560 ms |
| strict `F_FULLFSYNC` | 6.863 ms | 6.598 ms | 11.610 ms | 11.610 ms |

This selects the strict Linux investigation branch. The cold-boot repeat below
confirms the result. Compare sanitized Apple and Linux controller, cache, power,
and command state before implementing a kernel change.

The cold-boot repeat completed after a full reboot with no workload
intentionally running besides the probe:

| Mode | Mean sync | Median sync | P95 sync | Maximum sync |
| --- | ---: | ---: | ---: | ---: |
| ordinary `fsync()` | 1.107 ms | 1.087 ms | 1.300 ms | 1.300 ms |
| strict `F_FULLFSYNC` | 13.082 ms | 12.551 ms | 16.966 ms | 16.966 ms |

The strict path remains millisecond-scale after reboot, so the strict Linux
investigation is confirmed.
