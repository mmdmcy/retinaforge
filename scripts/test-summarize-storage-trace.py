#!/usr/bin/env python3
"""Unit tests for summarize-storage-trace.py."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("summarize-storage-trace.py")
SPEC = importlib.util.spec_from_file_location("summarize_storage_trace", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class TraceSummaryTests(unittest.TestCase):
    def summarize(self, text: str) -> dict[str, object]:
        with tempfile.TemporaryDirectory() as directory:
            trace = Path(directory) / "trace.txt"
            trace.write_text(text, encoding="utf-8")
            return MODULE.summarize(trace, (8, 0))

    def test_separates_pre_issue_and_device_time(self) -> None:
        result = self.summarize(
            """\
# entries-in-buffer/entries-written: 6/6
worker-1 [000] ..... 10.000000: block_rq_issue: 8,0 FF 0 () 0 + 0 none,0,0 [worker]
worker-1 [000] d..1. 10.200000: ata_qc_issue: ata_port=1 ata_dev=0 tag=4 proto=ATA_PROT_NODATA cmd=ATA_CMD_FLUSH_EXT  tf=(ea/00:00:00:00:00/00:00:00:00:00/a0)
<idle>-0 [001] d.h2. 10.900000: ata_qc_complete_done: ata_port=1 ata_dev=0 tag=4 flags=9{ ACTIVE IO } status={ DRDY } res=(40/00:00:00:00:00/00:00:00:00:00/00)
<idle>-0 [001] ..s1. 10.910000: block_rq_complete: 8,0 FF () 0 + 0 none,0,0 [0]
"""
        )
        latency = result["latency_ms"]
        self.assertEqual(latency["block_flush_to_ata_issue"]["p50"], 200.0)
        self.assertEqual(latency["ata_flush_issue_to_completion"]["p50"], 700.0)
        self.assertEqual(latency["block_flush_end_to_end"]["p50"], 910.0)
        self.assertFalse(result["trace_buffer"]["overflow_detected"])
        self.assertEqual(result["unmatched"]["ata_issues"], 0)

    def test_tracks_failed_flush_and_buffer_overflow(self) -> None:
        result = self.summarize(
            """\
# entries-in-buffer/entries-written: 3/9
worker-1 [000] ..... 1.000000: block_rq_issue: 8,0 FF 0 () 0 + 0 none,0,0 [worker]
worker-1 [000] d..1. 1.010000: ata_qc_issue: ata_port=1 ata_dev=0 tag=2 proto=ATA_PROT_NODATA cmd=ATA_CMD_FLUSH  tf=(e7/00:00:00:00:00/00:00:00:00:00/a0)
worker-1 [000] d..1. 1.020000: ata_qc_complete_failed: ata_port=1 ata_dev=0 tag=2 flags=9{ ACTIVE IO } status={ DRDY ERR } res=(41/04:00:00:00:00/00:00:00:00:00/00)
"""
        )
        self.assertTrue(result["trace_buffer"]["overflow_detected"])
        self.assertEqual(result["samples"]["ata_flush_failed"], 1)


if __name__ == "__main__":
    unittest.main()
