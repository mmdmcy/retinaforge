#!/usr/bin/env python3
"""Correlate AHCI PxCI samples with long ATA_CMD_FLUSH_EXT intervals."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

EVENT_PREFIX = re.compile(
    r"^.*?\s(?P<timestamp>\d+\.\d+):\s(?P<event>[a-zA-Z0-9_]+):\s(?P<body>.*)$"
)
ATA_ISSUE_BODY = re.compile(
    r"ata_port=(?P<port>\d+)\s+ata_dev=(?P<dev>\d+)\s+"
    r"tag=(?P<tag>\d+)\s+proto=\S+\s+cmd=(?P<cmd>\S+)"
)
ATA_COMPLETE_BODY = re.compile(
    r"ata_port=(?P<port>\d+)\s+ata_dev=(?P<dev>\d+)\s+"
    r"tag=(?P<tag>\d+)\s"
)
SAMPLE_LINE = re.compile(
    r"^(?P<t_ns>\d+)\s+"
    r"(?P<host_is>0x[0-9a-fA-F]+)\s+"
    r"(?P<pxis>0x[0-9a-fA-F]+)\s+"
    r"(?P<pxci>0x[0-9a-fA-F]+)\s+"
    r"(?P<pxsact>0x[0-9a-fA-F]+)\s+"
    r"(?P<pxtfd>0x[0-9a-fA-F]+)\s+"
    r"(?P<pxserr>0x[0-9a-fA-F]+)\s*$"
)


@dataclass
class FlushInterval:
    tag: int
    issued_at: float
    completed_at: float

    @property
    def duration_ms(self) -> float:
        return (self.completed_at - self.issued_at) * 1000.0


@dataclass
class AhciSample:
    t_s: float
    host_is: int
    pxis: int
    pxci: int
    pxsact: int
    pxtfd: int
    pxserr: int


def parse_trace_flushes(path: Path) -> list[FlushInterval]:
    outstanding: dict[tuple[int, int, int], float] = {}
    intervals: list[FlushInterval] = []

    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = EVENT_PREFIX.match(line)
        if not match:
            continue
        timestamp = float(match["timestamp"])
        event = match["event"]
        body = match["body"]
        if event == "ata_qc_issue":
            issue = ATA_ISSUE_BODY.search(body)
            if not issue or issue["cmd"] != "ATA_CMD_FLUSH_EXT":
                continue
            key = (int(issue["port"]), int(issue["dev"]), int(issue["tag"]))
            outstanding[key] = timestamp
        elif event in {"ata_qc_complete_done", "ata_qc_complete_failed"}:
            done = ATA_COMPLETE_BODY.search(body)
            if not done:
                continue
            key = (int(done["port"]), int(done["dev"]), int(done["tag"]))
            issued_at = outstanding.pop(key, None)
            if issued_at is None:
                continue
            intervals.append(
                FlushInterval(
                    tag=key[2],
                    issued_at=issued_at,
                    completed_at=timestamp,
                )
            )
    return intervals


def parse_samples(path: Path) -> list[AhciSample]:
    samples: list[AhciSample] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line or line.startswith("#"):
            continue
        match = SAMPLE_LINE.match(line)
        if not match:
            continue
        samples.append(
            AhciSample(
                t_s=int(match["t_ns"]) / 1_000_000_000.0,
                host_is=int(match["host_is"], 16),
                pxis=int(match["pxis"], 16),
                pxci=int(match["pxci"], 16),
                pxsact=int(match["pxsact"], 16),
                pxtfd=int(match["pxtfd"], 16),
                pxserr=int(match["pxserr"], 16),
            )
        )
    return samples


def classify_interval(
    interval: FlushInterval,
    samples: list[AhciSample],
    *,
    early_clear_fraction: float = 0.25,
) -> dict[str, object]:
    bit = 1 << interval.tag
    in_window = [
        sample
        for sample in samples
        if interval.issued_at <= sample.t_s <= interval.completed_at
    ]
    if len(in_window) < 3:
        return {
            "tag": interval.tag,
            "duration_ms": round(interval.duration_ms, 3),
            "classification": "insufficient_samples",
            "sample_count": len(in_window),
            "ci_set_fraction": None,
            "first_clear_offset_ms": None,
        }

    set_count = sum(1 for sample in in_window if sample.pxci & bit)
    ci_set_fraction = set_count / len(in_window)
    first_clear_offset_ms = None
    for sample in in_window:
        if not (sample.pxci & bit):
            first_clear_offset_ms = (sample.t_s - interval.issued_at) * 1000.0
            break

    if first_clear_offset_ms is not None and first_clear_offset_ms <= (
        interval.duration_ms * early_clear_fraction
    ):
        classification = "ci_cleared_early"
    elif ci_set_fraction >= 0.8:
        classification = "ci_held"
    elif first_clear_offset_ms is None:
        classification = "ci_held"
    else:
        classification = "ambiguous"

    return {
        "tag": interval.tag,
        "duration_ms": round(interval.duration_ms, 3),
        "classification": classification,
        "sample_count": len(in_window),
        "ci_set_fraction": round(ci_set_fraction, 3),
        "first_clear_offset_ms": None
        if first_clear_offset_ms is None
        else round(first_clear_offset_ms, 3),
    }


def summarize(
    trace_path: Path,
    sample_path: Path,
    *,
    min_duration_ms: float = 100.0,
) -> dict[str, object]:
    intervals = [
        interval
        for interval in parse_trace_flushes(trace_path)
        if interval.duration_ms >= min_duration_ms
    ]
    samples = parse_samples(sample_path)
    classified = [classify_interval(interval, samples) for interval in intervals]
    counts = {
        "ci_held": 0,
        "ci_cleared_early": 0,
        "ambiguous": 0,
        "insufficient_samples": 0,
    }
    for item in classified:
        counts[str(item["classification"])] += 1

    return {
        "long_flush_count": len(intervals),
        "sample_count": len(samples),
        "min_duration_ms": min_duration_ms,
        "counts": counts,
        "flushes": classified,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Correlate AHCI PxCI samples with long FLUSH_EXT intervals"
    )
    parser.add_argument("trace", type=Path, help="ftrace excerpt or controller-state")
    parser.add_argument("samples", type=Path, help="ahci-samples.txt")
    parser.add_argument(
        "--min-duration-ms",
        type=float,
        default=100.0,
        help="only classify flushes at least this long (default 100)",
    )
    parser.add_argument("--json", action="store_true", help="emit JSON")
    args = parser.parse_args()

    result = summarize(
        args.trace,
        args.samples,
        min_duration_ms=args.min_duration_ms,
    )
    if args.json:
        json.dump(result, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    else:
        counts = result["counts"]
        print(
            f"long_flushes={result['long_flush_count']} "
            f"samples={result['sample_count']} "
            f"ci_held={counts['ci_held']} "
            f"ci_cleared_early={counts['ci_cleared_early']} "
            f"ambiguous={counts['ambiguous']} "
            f"insufficient_samples={counts['insufficient_samples']}"
        )
        for item in result["flushes"]:
            print(
                f"tag={item['tag']} duration_ms={item['duration_ms']} "
                f"class={item['classification']} "
                f"ci_set_fraction={item['ci_set_fraction']} "
                f"first_clear_ms={item['first_clear_offset_ms']} "
                f"n={item['sample_count']}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
