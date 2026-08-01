#!/usr/bin/env python3
"""Unit tests for AHCI flush sample correlation."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


def load_module():
    import sys

    path = Path(__file__).resolve().parent / "summarize-ahci-flush-samples.py"
    spec = importlib.util.spec_from_file_location("ahci_flush_summary", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


MOD = load_module()


class AhciFlushSummaryTests(unittest.TestCase):
    def write(self, directory: Path, name: str, text: str) -> Path:
        path = directory / name
        path.write_text(text)
        return path

    def test_ci_held_for_long_flush(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            trace = self.write(
                root,
                "trace.txt",
                """
worker-1 [000] d..1. 10.000000: ata_qc_issue: ata_port=1 ata_dev=0 tag=4 proto=ATA_PROT_NODATA cmd=ATA_CMD_FLUSH_EXT
idle-0 [001] d.h2. 11.200000: ata_qc_complete_done: ata_port=1 ata_dev=0 tag=4 flags=9
""".lstrip(),
            )
            samples = self.write(
                root,
                "samples.txt",
                "".join(
                    f"{10_000_000_000 + i * 100_000_000} 0x00000001 0x00000000 "
                    f"0x00000010 0x00000000 0x00000050 0x00000000\n"
                    for i in range(13)
                ),
            )
            result = MOD.summarize(trace, samples, min_duration_ms=100.0)
            self.assertEqual(result["counts"]["ci_held"], 1)
            self.assertEqual(result["flushes"][0]["classification"], "ci_held")

    def test_ci_cleared_early(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            trace = self.write(
                root,
                "trace.txt",
                """
worker-1 [000] d..1. 20.000000: ata_qc_issue: ata_port=1 ata_dev=0 tag=7 proto=ATA_PROT_NODATA cmd=ATA_CMD_FLUSH_EXT
idle-0 [001] d.h2. 21.100000: ata_qc_complete_done: ata_port=1 ata_dev=0 tag=7 flags=9
""".lstrip(),
            )
            lines = []
            for i in range(12):
                t_ns = 20_000_000_000 + i * 100_000_000
                pxci = "0x00000080" if i == 0 else "0x00000000"
                lines.append(
                    f"{t_ns} 0x00000001 0x00000000 {pxci} "
                    "0x00000000 0x00000050 0x00000000\n"
                )
            samples = self.write(root, "samples.txt", "".join(lines))
            result = MOD.summarize(trace, samples, min_duration_ms=100.0)
            self.assertEqual(result["counts"]["ci_cleared_early"], 1)
            self.assertEqual(
                result["flushes"][0]["classification"], "ci_cleared_early"
            )

    def test_short_flushes_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            trace = self.write(
                root,
                "trace.txt",
                """
worker-1 [000] d..1. 30.000000: ata_qc_issue: ata_port=1 ata_dev=0 tag=2 proto=ATA_PROT_NODATA cmd=ATA_CMD_FLUSH_EXT
idle-0 [001] d.h2. 30.020000: ata_qc_complete_done: ata_port=1 ata_dev=0 tag=2 flags=9
""".lstrip(),
            )
            samples = self.write(
                root,
                "samples.txt",
                "30000000000 0x1 0x0 0x4 0x0 0x50 0x0\n"
                "30010000000 0x1 0x0 0x0 0x0 0x50 0x0\n",
            )
            result = MOD.summarize(trace, samples, min_duration_ms=100.0)
            self.assertEqual(result["long_flush_count"], 0)


if __name__ == "__main__":
    unittest.main()
