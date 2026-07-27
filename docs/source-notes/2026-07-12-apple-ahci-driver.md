# 2026-07-12 Apple AHCI Driver Comparison

- Checked: 2026-07-12 Europe/Amsterdam
- Researcher: Codex
- Scope: Apple storage behavior for Samsung `144d:1600` and the difference
  between ordinary macOS synchronization and Linux ext4 durability.
- Status: signed Apple driver inspected; no hidden fast durability command was
  found.

## Source Register

| Source | Authority | Checked | Status | Notes |
| --- | --- | --- | --- | --- |
| [Apple Security Update 2019-001 (Mojave)](https://support.apple.com/en-us/106742) | Apple package index | 2026-07-12 | Official | Supplies the signed Intel `AppleAHCIPort` and `IOAHCIBlockStorage` binaries used for inspection. |
| [Apple-hosted update image](https://updates.cdn-apple.com/2019/macos/061-27896-20191029-4810aeb4-94bd-4df0-85b1-548113a6d24e/SecUpd2019-001Mojave.dmg) | Apple CDN | 2026-07-12 | Official | SHA-256 `f08b2c3d368f8e82c67d437ab8586d13a6c99dffa14b3a14f597b0c3f782e2f8`. |
| [Apple `fsync(2)` manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fsync.2.html) | Apple documentation | 2026-07-12 | Archived, directly relevant | Ordinary macOS `fsync()` need not commit the drive's volatile cache; `F_FULLFSYNC` requests that stronger guarantee. |
| [Apple IOStorageFamily source](https://github.com/apple-oss-distributions/IOStorageFamily) | Apple open source | 2026-07-12 | Primary source | Defines separate barrier, FUA, and full device-synchronize operations. |

## Reproduction Metadata

- `AppleAHCIPort` version `329.260.5`, SHA-256
  `e977ef2a999488188dfae0855332134bb82627d078ff3fc9822dbd85e6377b49`.
- `IOAHCIBlockStorage` version `301.270.1`, SHA-256
  `507842a1858459c2f55f8f9b33540fae6646344376b5b61a380ef899f15df3a6`.
- Binaries were extracted locally from the official image and inspected with
  LLVM's Mach-O symbol and disassembly tools. The binaries and update image are
  ignored build inputs and are not committed.

## Driver Findings

### Exact controller branch

`AppleAHCI::ApplyWorkarounds()` explicitly matches vendor `0x144d`, device
`0x1600`. Its branch sets registry metadata including `sata-express`, vendor
name, and chipset name. It does not issue an ATA command or program a
controller register. There is no missing Apple initialization command to copy
from this model branch.

### Flush commands

`IOAHCIBlockStorageDriver::BuildATAFlushCacheCommand()` selects standard ATA
`FLUSH CACHE` (`E7h`) or `FLUSH CACHE EXT` (`EAh`) according to device
capability. Both commands were already tested directly on the target and both
settle near 820 ms after a dirty write.

### Write commands

`IOAHCIBlockStorageDriver::BuildATAReadWriteCommand()` builds:

- non-NCQ `READ/WRITE DMA` (`C8h`/`CAh`) or `READ/WRITE DMA EXT`
  (`25h`/`35h`); it does not substitute non-NCQ `WRITE DMA FUA EXT` (`3Dh`);
- NCQ `READ/WRITE FPDMA QUEUED` (`60h`/`61h`), setting the FUA device bit only
  when the request explicitly carries Apple's FUA flag.

The discarded Linux non-NCQ FUA patch therefore did not reproduce Apple's
normal path. More importantly, the target's Linux NCQ FUA and standard flush
paths already reproduce every strict durability command found in the Apple
driver, and all are slow.

## Conclusion

The evidence does not support a proprietary Apple command that makes a strict
flush fast. The macOS/Linux performance difference is primarily explained by
semantics: ordinary macOS `fsync()` permits data to remain in the drive's
volatile cache, while Linux ext4 normally gives `fsync()` the stronger
power-loss guarantee. Apple's strict path uses the same slow ATA operations.

This means a Linux mode that feels like ordinary macOS must deliberately adopt
weaker acknowledgment semantics, batch persistent writes elsewhere, or bypass
the internal device. It cannot honestly preserve Linux's normal `fsync()`
contract while the firmware takes about 0.8 seconds per persistence point.

## Recheck Triggers

- A trace from this exact Mac running macOS shows a vendor ATA opcode or
  controller register change absent from the inspected driver.
- A different Apple driver release contains a materially different
  `0x144d:0x1600` branch.
- A firmware package explicitly supports `APPLE SSD SM1024F / UXM6JA1Q`.
