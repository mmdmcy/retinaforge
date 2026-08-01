#!/usr/bin/env python3
"""Unit tests for in-kernel AHCI flush-reg sample classification."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


def load_module():
    path = Path(__file__).resolve().parent / "summarize-ahci-flush-reg.py"
    spec = importlib.util.spec_from_file_location("ahci_flush_reg_summary", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


mod = load_module()


def line(when: str, tag: int, age: int, pxci: int, ts: float = 1.0) -> str:
    return (
        f"[{ts:12.6f}] mbp-ahci-flush-reg when={when} tag={tag} age_ms={age} "
        f"host_is=0x0 pxis=0x0 pxci=0x{pxci:x} pxsact=0x0 pxtfd=0x0 pxserr=0x0"
    )


class FlushRegSummaryTests(unittest.TestCase):
    def test_ci_held(self) -> None:
        text = "\n".join(
            [
                line("issue", 3, 0, 0x8, 10.0),
                line("timer", 3, 50, 0x8, 10.05),
                line("timer", 3, 500, 0x8, 10.5),
                line("complete", 3, 1100, 0x0, 11.1),
            ]
        )
        result = mod.summarize(text)
        self.assertEqual(result["verdict"], "ci_held")
        self.assertEqual(result["flushes"][0]["classification"], "ci_held")

    def test_ci_cleared_early(self) -> None:
        text = "\n".join(
            [
                line("issue", 2, 0, 0x4, 20.0),
                line("timer", 2, 50, 0x0, 20.05),
                line("timer", 2, 500, 0x0, 20.5),
                line("complete", 2, 1130, 0x0, 21.13),
            ]
        )
        result = mod.summarize(text)
        self.assertEqual(result["verdict"], "ci_cleared_early")
        self.assertEqual(
            result["flushes"][0]["classification"], "ci_cleared_early"
        )

    def test_tag_reuse_pairs_chronologically(self) -> None:
        text = "\n".join(
            [
                line("issue", 1, 0, 0x2, 1.0),
                line("complete", 1, 5, 0x0, 1.005),
                line("issue", 1, 0, 0x2, 2.0),
                line("timer", 1, 50, 0x2, 2.05),
                line("timer", 1, 1000, 0x2, 3.0),
                line("complete", 1, 1133, 0x0, 3.133),
            ]
        )
        result = mod.summarize(text)
        self.assertEqual(result["flush_count"], 2)
        self.assertEqual(result["long_flush_count"], 1)
        self.assertEqual(result["verdict"], "ci_held")

    def test_short_flushes_ignored(self) -> None:
        text = "\n".join(
            [
                line("issue", 1, 0, 0x2),
                line("complete", 1, 12, 0x0),
            ]
        )
        result = mod.summarize(text)
        self.assertEqual(result["long_flush_count"], 0)
        self.assertEqual(result["verdict"], "no_long_flushes")


if __name__ == "__main__":
    unittest.main()
