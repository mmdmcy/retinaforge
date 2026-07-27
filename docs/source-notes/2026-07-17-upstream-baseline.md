# 2026-07-17 Upstream Linux Baseline

- Checked: `2026-07-17 Europe/Amsterdam`
- Researcher: `Codex`
- Scope: select and authenticate the first current upstream bare-metal Linux
  baseline for `MacBookPro11,3` storage-state capture.
- Status: source authenticated and host-side appliance QA complete; physical
  hardware capture pending.

## Questions

- Which maintained upstream kernel should establish the new baseline?
- Does it retain the known `144d:1600` no-MSI quirk?
- Does it contain the current Apple EFI-stub product handling needed by later
  graphics work?
- How is the source authenticated independently of a downloaded archive hash?

## Source Register

| Source | Authority | Checked | Status | Notes |
| --- | --- | --- | --- | --- |
| [kernel.org](https://www.kernel.org/) | Official | 2026-07-17 | Current at check | Listed Linux `7.1.3` as the stable release and `7.2-rc3` as mainline. The stable release was selected over a release candidate. |
| [Kernel release signature guide](https://www.kernel.org/signature.html) | Official | 2026-07-17 | Current at check | Documents signed Git tags and kernel.org WKD key retrieval. |
| [Linux stable Git](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/) | Official | 2026-07-17 | Pinned | Source remote for signed tag `v7.1.3`. |

## Local Verification Record

- `v7.1.3` resolves to commit
  `199c9959d3a9b53f346c221757fc7ac507fbac50` with subject `Linux 7.1.3`.
- The tag signature validates in an isolated keyring as Greg
  Kroah-Hartman's key with fingerprint
  `647F28654894E3BD457199BE38DBBDC86092693E`.
- `drivers/ata/ahci.c` still maps Samsung PCI device `0x1600` to
  `board_ahci_no_msi`.
- `drivers/firmware/efi/libstub/x86-stub.c` explicitly includes
  `MacBookPro11,3` in Apple product matching.
- No kernel source modification is present in the baseline artifact.

## Product Implications

- Distribution choice is not part of this first discriminator; it boots the
  authenticated upstream kernel directly against the physical hardware.
- The first capture measures modern upstream behavior before a local patch is
  proposed.
- Linux `7.2-rc3` may be tested later only if the stable baseline identifies a
  reason or a relevant change; a release candidate is not needed merely to be
  newer.

## Recheck Triggers

- Recheck kernel.org before beginning a new patch series or reporting the
  baseline as "current."
- Rebase after one concrete mechanism is identified, not during initial state
  capture.
- Recheck signer identity and the kernel project's assisted-contribution policy
  before any upstream submission.

## Open Questions

- Which Linux-visible controller or command-state difference explains the
  millisecond-scale macOS `F_FULLFSYNC` result?
- Is that difference initialized by firmware state, AHCI/libata setup, cache
  policy, command ordering, or another layer?
