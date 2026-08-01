#!/usr/bin/env python3
"""Extract flush/write command-pattern metrics from a Linux storage capture.

Reads appliance controller-state.txt (ftrace block + libata events) and optional
ahci-flush-reg.txt. Emits aggregates suitable for Darwin-versus-Linux comparison.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from collections import Counter, deque
from pathlib import Path

EVENT_PREFIX = re.compile(
    r"^.*?\s(?P<timestamp>\d+\.\d+):\s(?P<event>[a-zA-Z0-9_]+):\s(?P<body>.*)$"
)
BLOCK_ISSUE = re.compile(
    r"(?P<major>\d+),(?P<minor>\d+)\s+(?P<rwbs>\S+)\s+(?P<bytes>\d+)\s+"
)
ATA_ISSUE = re.compile(
    r"ata_port=(?P<port>\d+)\s+ata_dev=(?P<dev>\d+)\s+"
    r"tag=(?P<tag>\d+)\s+proto=\S+\s+cmd=(?P<cmd>\S+)"
)
ATA_COMPLETE = re.compile(
    r"ata_port=(?P<port>\d+)\s+ata_dev=(?P<dev>\d+)\s+tag=(?P<tag>\d+)"
)
FLUSH_REG = re.compile(
    r"mbp-ahci-flush-reg when=(?P<when>\w+) tag=(?P<tag>\d+) age_ms=(?P<age>\d+) "
    r".* pxci=(?P<pxci>0x[0-9a-fA-F]+)"
)
FLUSH_COMMANDS = {"ATA_CMD_FLUSH", "ATA_CMD_FLUSH_EXT"}


def percentile(values: list[float], percent: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    rank = max(0, math.ceil(percent / 100 * len(ordered)) - 1)
    return ordered[rank]


def distribution(values: list[float]) -> dict[str, float] | None:
    if not values:
        return None
    return {
        "min": round(min(values), 3),
        "p50": round(percentile(values, 50) or 0.0, 3),
        "p95": round(percentile(values, 95) or 0.0, 3),
        "max": round(max(values), 3),
        "count": len(values),
    }


def pair_flush_reg(text: str) -> list[dict]:
    open_by_tag: dict[int, dict] = {}
    flushes: list[dict] = []
    for line in text.splitlines():
        match = FLUSH_REG.search(line)
        if not match:
            continue
        tag = int(match["tag"])
        when = match["when"]
        age = int(match["age"])
        pxci = int(match["pxci"], 16)
        ci_bit = bool(pxci & (1 << tag))
        if when == "issue":
            open_by_tag[tag] = {"tag": tag, "timers": []}
        elif when == "timer":
            current = open_by_tag.get(tag)
            if current is not None:
                current["timers"].append({"age_ms": age, "ci_bit": ci_bit})
        elif when == "complete":
            current = open_by_tag.pop(tag, None)
            if current is None:
                continue
            timers = current["timers"]
            if not timers:
                classification = "no_timer_sample"
            elif any(timer["ci_bit"] for timer in timers):
                classification = "ci_held"
            else:
                classification = "ci_cleared_early"
            flushes.append(
                {
                    "tag": tag,
                    "complete_age_ms": age,
                    "classification": classification,
                }
            )
    return flushes


def extract(controller_state: Path, flush_reg: Path | None = None) -> dict:
    ata_issue_counts: Counter[str] = Counter()
    block_rwbs_counts: Counter[str] = Counter()
    flush_issue_times: list[float] = []
    flush_complete_ages_ms: list[float] = []
    outstanding: dict[tuple[int, int, int], float] = {}
    writes_since_flush = 0
    bytes_since_flush = 0
    writes_between_flushes: list[int] = []
    bytes_between_flushes: list[int] = []
    first_ts: float | None = None
    last_ts: float | None = None

    text = controller_state.read_text(encoding="utf-8", errors="replace")
    for line in text.splitlines():
        event_match = EVENT_PREFIX.match(line)
        if not event_match:
            continue
        timestamp = float(event_match["timestamp"])
        event = event_match["event"]
        body = event_match["body"]
        if first_ts is None:
            first_ts = timestamp
        last_ts = timestamp

        if event == "block_rq_issue":
            block_match = BLOCK_ISSUE.match(body)
            if not block_match:
                continue
            rwbs = block_match["rwbs"]
            block_rwbs_counts[rwbs] += 1
            if rwbs.startswith("W"):
                writes_since_flush += 1
                bytes_since_flush += int(block_match["bytes"])
            continue

        if event == "ata_qc_issue":
            ata_match = ATA_ISSUE.search(body)
            if not ata_match:
                continue
            cmd = ata_match["cmd"]
            ata_issue_counts[cmd] += 1
            key = (
                int(ata_match["port"]),
                int(ata_match["dev"]),
                int(ata_match["tag"]),
            )
            if cmd in FLUSH_COMMANDS:
                writes_between_flushes.append(writes_since_flush)
                bytes_between_flushes.append(bytes_since_flush)
                writes_since_flush = 0
                bytes_since_flush = 0
                flush_issue_times.append(timestamp)
                outstanding[key] = timestamp
            continue

        if event in {
            "ata_qc_complete_done",
            "ata_qc_complete_internal",
            "ata_qc_complete_failed",
        }:
            ata_match = ATA_COMPLETE.search(body)
            if not ata_match:
                continue
            key = (
                int(ata_match["port"]),
                int(ata_match["dev"]),
                int(ata_match["tag"]),
            )
            issued_at = outstanding.pop(key, None)
            if issued_at is not None:
                flush_complete_ages_ms.append((timestamp - issued_at) * 1000.0)

    gaps_ms = [
        (flush_issue_times[i] - flush_issue_times[i - 1]) * 1000.0
        for i in range(1, len(flush_issue_times))
    ]
    window_s = (
        (last_ts - first_ts) if first_ts is not None and last_ts is not None else 0.0
    )
    long_ages = [age for age in flush_complete_ages_ms if age >= 100.0]
    short_ages = [age for age in flush_complete_ages_ms if age < 100.0]

    flush_reg_summary = None
    if flush_reg and flush_reg.is_file():
        reg_flushes = pair_flush_reg(
            flush_reg.read_text(encoding="utf-8", errors="replace")
        )
        long_reg = [item for item in reg_flushes if item["complete_age_ms"] >= 100]
        classes = Counter(item["classification"] for item in long_reg)
        flush_reg_summary = {
            "flush_count": len(reg_flushes),
            "long_flush_count": len(long_reg),
            "long_class_counts": dict(classes),
            "verdict": (
                "ci_held"
                if long_reg and set(classes) == {"ci_held"}
                else "ci_cleared_early"
                if long_reg and set(classes) == {"ci_cleared_early"}
                else "mixed"
                if long_reg
                else "no_long_flushes"
            ),
        }

    first_long_index = next(
        (i for i, age in enumerate(flush_complete_ages_ms) if age >= 100.0),
        None,
    )

    return {
        "os": "linux",
        "source": str(controller_state),
        "trace_window_s": round(window_s, 3),
        "ata_issue_counts": dict(ata_issue_counts),
        "block_rwbs_counts": dict(block_rwbs_counts),
        "flush_ext_count": ata_issue_counts.get("ATA_CMD_FLUSH_EXT", 0),
        "fpdma_write_count": ata_issue_counts.get("ATA_CMD_FPDMA_WRITE", 0),
        "fpdma_read_count": ata_issue_counts.get("ATA_CMD_FPDMA_READ", 0),
        "flushes_per_s": round(len(flush_issue_times) / window_s, 3)
        if window_s > 0
        else None,
        "inter_flush_gap_ms": distribution(gaps_ms),
        "flush_completion_ms": distribution(flush_complete_ages_ms),
        "short_flush_completion_ms": distribution(short_ages),
        "long_flush_completion_ms": distribution(long_ages),
        "long_flush_count": len(long_ages),
        "short_flush_count": len(short_ages),
        "writes_between_flushes": distribution(
            [float(value) for value in writes_between_flushes]
        ),
        "bytes_between_flushes": distribution(
            [float(value) for value in bytes_between_flushes]
        ),
        "first_long_flush_index": first_long_index,
        "flush_reg": flush_reg_summary,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("controller_state", type=Path)
    parser.add_argument(
        "--flush-reg",
        type=Path,
        help="optional ahci-flush-reg.txt from the same capture",
    )
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    flush_reg = args.flush_reg
    if flush_reg is None:
        candidate = args.controller_state.parent / "ahci-flush-reg.txt"
        if candidate.is_file():
            flush_reg = candidate
    result = extract(args.controller_state, flush_reg)
    if args.json:
        json.dump(result, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    else:
        print(
            f"flushes={result['flush_ext_count']} "
            f"fpdma_writes={result['fpdma_write_count']} "
            f"long={result['long_flush_count']} "
            f"short={result['short_flush_count']} "
            f"window_s={result['trace_window_s']}"
        )
        if result["flush_completion_ms"]:
            dist = result["flush_completion_ms"]
            print(
                f"flush_completion_ms p50={dist['p50']} p95={dist['p95']} "
                f"max={dist['max']}"
            )
        if result["inter_flush_gap_ms"]:
            dist = result["inter_flush_gap_ms"]
            print(
                f"inter_flush_gap_ms p50={dist['p50']} p95={dist['p95']} "
                f"max={dist['max']}"
            )
        if result["flush_reg"]:
            print(
                f"flush_reg verdict={result['flush_reg']['verdict']} "
                f"long_classes={result['flush_reg']['long_class_counts']}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
