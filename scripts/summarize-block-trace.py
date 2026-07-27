#!/usr/bin/env python3
"""Summarize flush-like request latency from a ftrace block-event capture.

The latency probe records `block_rq_issue` and `block_rq_complete` events. This
tool pairs flush-like events for one block device in trace order. It is a
diagnostic summary, not a replacement for full block-layer attribution.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from collections import deque
from pathlib import Path


EVENT = re.compile(
    r"^.*?\s(?P<timestamp>\d+\.\d+):\s"
    r"block_rq_(?P<kind>issue|complete):\s"
    r"(?P<major>\d+),(?P<minor>\d+)\s+(?P<rwbs>\S+)\s"
)


def percentile(values: list[float], percent: float) -> float:
    ordered = sorted(values)
    rank = max(0, math.ceil(percent / 100 * len(ordered)) - 1)
    return ordered[rank]


def parse_device(value: str) -> tuple[int, int]:
    try:
        major, minor = (int(part, 10) for part in value.split(",", 1))
    except ValueError as exc:
        raise argparse.ArgumentTypeError("device must have MAJOR,MINOR form") from exc
    return major, minor


def summarize(path: Path, device: tuple[int, int]) -> dict[str, object]:
    outstanding: deque[float] = deque()
    latencies_ms: list[float] = []
    unmatched_completions = 0

    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = EVENT.match(line)
        if not match:
            continue
        if (int(match["major"]), int(match["minor"])) != device:
            continue
        if "F" not in match["rwbs"]:
            continue

        timestamp = float(match["timestamp"])
        if match["kind"] == "issue":
            outstanding.append(timestamp)
        elif outstanding:
            latencies_ms.append((timestamp - outstanding.popleft()) * 1_000)
        else:
            unmatched_completions += 1

    result: dict[str, object] = {
        "device": f"{device[0]},{device[1]}",
        "flush_like_issues_without_completion": len(outstanding),
        "flush_like_completions_without_issue": unmatched_completions,
        "flush_like_samples": len(latencies_ms),
    }
    if latencies_ms:
        result["latency_ms"] = {
            "min": round(min(latencies_ms), 3),
            "p50": round(percentile(latencies_ms, 50), 3),
            "p95": round(percentile(latencies_ms, 95), 3),
            "p99": round(percentile(latencies_ms, 99), 3),
            "max": round(max(latencies_ms), 3),
        }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, help="local ftrace text capture")
    parser.add_argument(
        "--device",
        type=parse_device,
        default=(8, 0),
        help="block device major,minor (default: 8,0)",
    )
    parser.add_argument("--json", action="store_true", help="emit JSON")
    args = parser.parse_args()

    if not args.trace.is_file():
        parser.error(f"not a readable trace file: {args.trace}")

    result = summarize(args.trace, args.device)
    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        print(f"device: {result['device']}")
        print(f"flush-like samples: {result['flush_like_samples']}")
        print(
            "unmatched issue/complete: "
            f"{result['flush_like_issues_without_completion']}"
            f"/{result['flush_like_completions_without_issue']}"
        )
        latency = result.get("latency_ms")
        if latency:
            print("latency ms: " + " ".join(f"{key}={value}" for key, value in latency.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
