#!/usr/bin/env python3
"""Unit tests for flush-pattern extract and compare helpers."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


def load(name: str, filename: str):
    path = Path(__file__).resolve().parent / filename
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


extract_mod = load("extract_flush_pattern", "extract-flush-pattern.py")
compare_mod = load("compare_flush_patterns", "compare-flush-patterns.py")


TRACE = """
# entries-in-buffer/entries-written: 10/10
    task-1     [000] .....     1.000000: block_rq_issue: 8,0 W 1048576 () 100 + 2048 be,0,4 [task]
    task-1     [000] d..1.     1.000010: ata_qc_issue: ata_port=1 ata_dev=0 tag=1 proto=ATA_PROT_NCQ cmd=ATA_CMD_FPDMA_WRITE  tf=(61/00:00:00:00:00/00:00:00:00:00/40)
    task-1     [000] .....     1.010000: block_rq_issue: 8,0 FF 0 () 0 + 0 none,0,0 [task]
    task-1     [000] d..1.     1.010005: ata_qc_issue: ata_port=1 ata_dev=0 tag=2 proto=ATA_PROT_NODATA cmd=ATA_CMD_FLUSH_EXT  tf=(ea/00:00:00:00:00/00:00:00:00:00/a0)
    idle-0     [000] d.h2.     1.020000: ata_qc_complete_done: ata_port=1 ata_dev=0 tag=2 flags=9{ ACTIVE IO } status={ DRDY }
    task-1     [000] .....     2.000000: block_rq_issue: 8,0 W 1048576 () 200 + 2048 be,0,4 [task]
    task-1     [000] d..1.     2.000010: ata_qc_issue: ata_port=1 ata_dev=0 tag=3 proto=ATA_PROT_NCQ cmd=ATA_CMD_FPDMA_WRITE  tf=(61/00:00:00:00:00/00:00:00:00:00/40)
    task-1     [000] .....     2.010000: block_rq_issue: 8,0 FF 0 () 0 + 0 none,0,0 [task]
    task-1     [000] d..1.     2.010005: ata_qc_issue: ata_port=1 ata_dev=0 tag=4 proto=ATA_PROT_NODATA cmd=ATA_CMD_FLUSH_EXT  tf=(ea/00:00:00:00:00/00:00:00:00:00/a0)
    idle-0     [000] d.h2.     3.140005: ata_qc_complete_done: ata_port=1 ata_dev=0 tag=4 flags=9{ ACTIVE IO } status={ DRDY }
"""

FLUSH_REG = """
[    2.010010] mbp-ahci-flush-reg when=issue tag=4 age_ms=0 host_is=0x0 pxis=0x0 pxci=0x10 pxsact=0x0 pxtfd=0xc0 pxserr=0x0
[    2.060010] mbp-ahci-flush-reg when=timer tag=4 age_ms=50 host_is=0x0 pxis=0x0 pxci=0x10 pxsact=0x0 pxtfd=0xc0 pxserr=0x0
[    3.140010] mbp-ahci-flush-reg when=complete tag=4 age_ms=1130 host_is=0x1 pxis=0x0 pxci=0x0 pxsact=0x0 pxtfd=0x50 pxserr=0x0
"""

DARWIN = """
config,os=darwin,directory=/tmp,iterations=64,bytes_per_write=1048576,flush_only_bytes=67108864
summary,os=darwin,mode=isolated-F_FULLFSYNC,count=12,mean_sync_ms=8.000,median_sync_ms=7.500,p95_sync_ms=12.000,max_sync_ms=13.000,long_sync_count=0,first_long_index=none,wall_ms=120.000,syncs_per_s=100.000
summary,os=darwin,mode=sustained-F_FULLFSYNC,count=64,mean_sync_ms=9.000,median_sync_ms=8.500,p95_sync_ms=15.000,max_sync_ms=20.000,long_sync_count=0,first_long_index=none,wall_ms=800.000,syncs_per_s=80.000
summary,os=darwin,mode=flush-only-F_FULLFSYNC,count=64,mean_sync_ms=6.000,median_sync_ms=5.500,p95_sync_ms=10.000,max_sync_ms=11.000,long_sync_count=0,first_long_index=none,wall_ms=500.000,syncs_per_s=128.000
"""


class FlushPatternTests(unittest.TestCase):
    def test_extract_linux_pattern(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            controller = root / "controller-state.txt"
            flush_reg = root / "ahci-flush-reg.txt"
            controller.write_text(TRACE)
            flush_reg.write_text(FLUSH_REG)
            result = extract_mod.extract(controller, flush_reg)
            self.assertEqual(result["flush_ext_count"], 2)
            self.assertEqual(result["fpdma_write_count"], 2)
            self.assertEqual(result["long_flush_count"], 1)
            self.assertEqual(result["short_flush_count"], 1)
            self.assertEqual(result["flush_reg"]["verdict"], "ci_held")
            self.assertEqual(result["first_long_flush_index"], 1)

    def test_compare_flags_darwin_stays_fast(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            linux_json = root / "linux.json"
            darwin_log = root / "darwin.log"
            controller = root / "controller-state.txt"
            controller.write_text(TRACE)
            (root / "ahci-flush-reg.txt").write_text(FLUSH_REG)
            linux = extract_mod.extract(controller, root / "ahci-flush-reg.txt")
            linux_json.write_text(
                __import__("json").dumps(linux)
            )
            darwin_log.write_text(DARWIN)
            result = compare_mod.compare(
                compare_mod.load_linux(linux_json),
                compare_mod.parse_darwin(darwin_log),
            )
            self.assertIn(
                "darwin_stays_fast_under_sustained_fullfsync_while_linux_has_long_flushes",
                result["hypotheses"],
            )


if __name__ == "__main__":
    unittest.main()
