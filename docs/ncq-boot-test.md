# One-Time NCQ Boot Test

This is the first user-present test. It restores the upstream configuration
already encoded in Linux for PCI `144d:1600`: MSI stays disabled, while the
manual `libata.force=noncq` override is absent for exactly one boot.

## Safety Contract

- Do not run while the owner is away.
- Do not change `GRUB_DEFAULT`, `/etc/default/grub`, encryption, or filesystem
  settings for this test.
- The generated entry has a fixed ID and `grub-reboot` selects it once only.
  The existing saved stock-kernel entry remains the fallback.
- The test requires the normal LUKS passphrase at boot. No key is stored or
  transmitted.

## Agent Workflow

When the owner confirms they are at the MacBook:

```bash
sudo scripts/create-ncq-test-entry.sh --install --arm-next-boot --yes
```

Confirm that the command only armed the next boot; it must not reboot. The
owner then restarts the computer and unlocks LUKS normally.

After SSH returns, verify that `/proc/cmdline` does not contain
`libata.force=noncq`. Also verify the expected feature transition:

```bash
cat /sys/block/sda/device/queue_depth
cat /sys/block/sda/queue/fua
```

The baseline values are `1` and `0`; the restored configuration should expose
a queue depth greater than one. Linux 6.8 leaves libata FUA disabled by
default, so FUA may remain `0` during the NCQ-only test. Then run:

```bash
sudo scripts/run-latency-probe.sh --yes --size-mib 16 \
  --trace-out captures/ncq-restored.trace
scripts/summarize-block-trace.py captures/ncq-restored.trace
```

Run a normal package or small file-write workload only after the probe. Record
the raw result in ignored local notes and publish only a sanitized aggregate
comparison with the `noncq` baseline.

## Recovery

If the test entry fails to boot, restart normally. GRUB consumes `next_entry`
after the first attempt and returns to the unchanged saved stock entry. Do not
edit GRUB interactively, change LUKS, or force a SATA link-speed cap.

After a successful comparison, remove the temporary entry:

```bash
sudo scripts/create-ncq-test-entry.sh --remove --yes
```

If the NCQ test passes, remove the manual `noncq` parameter separately in a
user-present maintenance step and regenerate GRUB; do not combine that durable
change with the first test boot.

If NCQ is active and error-free but FUA remains `0` and flush latency remains
high, install the next one-use candidate with:

```bash
sudo scripts/create-ncq-test-entry.sh --install --enable-fua --replace \
  --arm-next-boot --yes
```

The NCQ + FUA candidate must expose queue depth greater than one and FUA `1`
before its latency probe is accepted.
