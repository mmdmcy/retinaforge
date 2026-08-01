#!/usr/bin/env python3
"""Separate block flush queueing from ATA flush issue-to-completion time."""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from collections import deque
from dataclasses import dataclass
from pathlib import Path


EVENT_PREFIX = re.compile(
    r"^.*?\s(?P<timestamp>\d+\.\d+):\s(?P<event>[a-zA-Z0-9_]+):\s(?P<body>.*)$"
)
BLOCK_BODY = re.compile(
    r"(?P<major>\d+),(?P<minor>\d+)\s+(?P<rwbs>\S+)\s"
)
BLOCK_COMPLETION_ERROR = re.compile(r"\[(?P<error>-?\d+)\]\s*$")
ATA_ISSUE_BODY = re.compile(
    r"ata_port=(?P<port>\d+)\s+ata_dev=(?P<dev>\d+)\s+"
    r"tag=(?P<tag>\d+)\s+proto=\S+\s+cmd=(?P<cmd>\S+)"
)
ATA_COMPLETE_BODY = re.compile(
    r"ata_port=(?P<port>\d+)\s+ata_dev=(?P<dev>\d+)\s+"
    r"tag=(?P<tag>\d+)\s"
)
BUFFER_COUNTS = re.compile(
    r"entries-in-buffer/entries-written:\s*(?P<buffered>\d+)/(?P<written>\d+)"
)
FLUSH_COMMANDS = {"ATA_CMD_FLUSH", "ATA_CMD_FLUSH_EXT"}


@dataclass(frozen=True)
class AtaCommand:
    issued_at: float
    command: str


def percentile(values: list[float], percent: float) -> float:
    ordered = sorted(values)
    rank = max(0, math.ceil(percent / 100 * len(ordered)) - 1)
    return ordered[rank]


def distribution(values: list[float]) -> dict[str, float] | None:
    if not values:
        return None
    return {
        "min": round(min(values), 3),
        "p50": round(percentile(values, 50), 3),
        "p95": round(percentile(values, 95), 3),
        "p99": round(percentile(values, 99), 3),
        "max": round(max(values), 3),
    }


def parse_device(value: str) -> tuple[int, int]:
    try:
        major, minor = (int(part, 10) for part in value.split(",", 1))
    except ValueError as exc:
        raise argparse.ArgumentTypeError("device must have MAJOR,MINOR form") from exc
    return major, minor


def summarize(path: Path, device: tuple[int, int]) -> dict[str, object]:
    block_flushes: deque[float] = deque()
    block_to_ata: deque[float] = deque()
    ata_outstanding: dict[tuple[int, int, int], AtaCommand] = {}

    block_latencies_ms: list[float] = []
    pre_issue_latencies_ms: list[float] = []
    ata_latencies_ms: list[float] = []
    flush_ext_issued = 0
    failed_flushes = 0
    failed_block_flushes = 0
    failed_ata_commands = 0
    unmatched_block_completions = 0
    unmatched_ata_completions = 0
    duplicate_ata_issues = 0
    unparseable_block_completions = 0
    buffered_entries: int | None = None
    written_entries: int | None = None

    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        counts = BUFFER_COUNTS.search(line)
        if counts:
            buffered_entries = int(counts["buffered"])
            written_entries = int(counts["written"])

        event_match = EVENT_PREFIX.match(line)
        if not event_match:
            continue
        timestamp = float(event_match["timestamp"])
        event = event_match["event"]
        body = event_match["body"]

        if event in {"block_rq_issue", "block_rq_complete"}:
            block_match = BLOCK_BODY.match(body)
            if not block_match:
                continue
            if (
                int(block_match["major"]),
                int(block_match["minor"]),
            ) != device or not block_match["rwbs"].startswith("F"):
                continue
            if event == "block_rq_issue":
                block_flushes.append(timestamp)
                block_to_ata.append(timestamp)
            elif block_flushes:
                issued_at = block_flushes.popleft()
                completion_error = BLOCK_COMPLETION_ERROR.search(body)
                if completion_error is None:
                    unparseable_block_completions += 1
                    continue
                if int(completion_error["error"]):
                    failed_block_flushes += 1
                    continue
                block_latencies_ms.append(
                    (timestamp - issued_at) * 1_000
                )
            else:
                unmatched_block_completions += 1
            continue

        if event == "ata_qc_issue":
            issue_match = ATA_ISSUE_BODY.search(body)
            if not issue_match:
                continue
            key = (
                int(issue_match["port"]),
                int(issue_match["dev"]),
                int(issue_match["tag"]),
            )
            command = issue_match["cmd"]
            if key in ata_outstanding:
                duplicate_ata_issues += 1
                continue
            ata_outstanding[key] = AtaCommand(timestamp, command)
            if command in FLUSH_COMMANDS and block_to_ata:
                pre_issue_latencies_ms.append(
                    (timestamp - block_to_ata.popleft()) * 1_000
                )
            if command == "ATA_CMD_FLUSH_EXT":
                flush_ext_issued += 1
            continue

        if event in {"ata_qc_complete_done", "ata_qc_complete_failed"}:
            complete_match = ATA_COMPLETE_BODY.search(body)
            if not complete_match:
                continue
            key = (
                int(complete_match["port"]),
                int(complete_match["dev"]),
                int(complete_match["tag"]),
            )
            if key not in ata_outstanding:
                unmatched_ata_completions += 1
                continue
            command = ata_outstanding.pop(key)
            if event == "ata_qc_complete_failed":
                failed_ata_commands += 1
                if command.command in FLUSH_COMMANDS:
                    failed_flushes += 1
                continue
            if command.command in FLUSH_COMMANDS:
                ata_latencies_ms.append((timestamp - command.issued_at) * 1_000)

    unmatched_ata_issues = len(ata_outstanding)
    result: dict[str, object] = {
        "device": f"{device[0]},{device[1]}",
        "trace_buffer": {
            "entries_in_buffer": buffered_entries,
            "entries_written": written_entries,
            "overflow_detected": (
                buffered_entries is not None
                and written_entries is not None
                and written_entries > buffered_entries
            ),
        },
        "samples": {
            "block_flush_end_to_end": len(block_latencies_ms),
            "block_flush_to_ata_issue": len(pre_issue_latencies_ms),
            "ata_flush_issue_to_completion": len(ata_latencies_ms),
            "ata_flush_ext_issued": flush_ext_issued,
            "block_flush_failed": failed_block_flushes,
            "ata_flush_failed": failed_flushes,
            "ata_commands_failed": failed_ata_commands,
        },
        "unmatched": {
            "block_issues": len(block_flushes),
            "block_completions": unmatched_block_completions,
            "block_flushes_without_ata_issue": len(block_to_ata),
            "ata_issues": unmatched_ata_issues,
            "ata_completions": unmatched_ata_completions,
            "duplicate_ata_issues": duplicate_ata_issues,
            "unparseable_block_completions": unparseable_block_completions,
        },
        "latency_ms": {
            "block_flush_end_to_end": distribution(block_latencies_ms),
            "block_flush_to_ata_issue": distribution(pre_issue_latencies_ms),
            "ata_flush_issue_to_completion": distribution(ata_latencies_ms),
        },
    }
    return result


def acceptance_errors(result: dict[str, object]) -> list[str]:
    errors: list[str] = []
    trace_buffer = result["trace_buffer"]
    samples = result["samples"]
    unmatched = result["unmatched"]

    if (
        trace_buffer["entries_in_buffer"] is None
        or trace_buffer["entries_written"] is None
    ):
        errors.append("trace buffer accounting is unavailable")
    elif trace_buffer["overflow_detected"]:
        errors.append("trace buffer overflowed")

    sample_names = (
        "block_flush_end_to_end",
        "block_flush_to_ata_issue",
        "ata_flush_issue_to_completion",
    )
    for name in sample_names:
        if samples[name] < 1:
            errors.append(f"no {name} samples")
    if len({samples[name] for name in sample_names}) != 1:
        errors.append("block and ATA flush sample counts differ")
    if samples["ata_flush_ext_issued"] < 1:
        errors.append("no ATA_CMD_FLUSH_EXT command was issued")
    if samples["ata_flush_failed"]:
        errors.append("one or more ATA flushes failed")
    if samples["block_flush_failed"]:
        errors.append("one or more block flushes failed")
    if samples["ata_commands_failed"]:
        errors.append("one or more ATA commands failed")
    for name, count in unmatched.items():
        if count:
            errors.append(f"unmatched {name}: {count}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, help="ftrace text capture or full report")
    parser.add_argument(
        "--device",
        type=parse_device,
        default=(8, 0),
        help="physical block device major,minor (default: 8,0)",
    )
    parser.add_argument("--json", action="store_true", help="emit JSON")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="exit nonzero unless every block and ATA flush is matched and successful",
    )
    args = parser.parse_args()

    if not args.trace.is_file():
        parser.error(f"not a readable trace: {args.trace}")

    result = summarize(args.trace, args.device)
    errors = acceptance_errors(result)
    result["acceptable"] = not errors
    result["acceptance_errors"] = errors
    if args.json:
        print(json.dumps(result, sort_keys=True))
        return int(args.strict and bool(errors))

    print(f"device: {result['device']}")
    trace_buffer = result["trace_buffer"]
    print(
        "trace buffer: "
        f"{trace_buffer['entries_in_buffer']}/{trace_buffer['entries_written']} "
        f"overflow={trace_buffer['overflow_detected']}"
    )
    samples = result["samples"]
    print(
        "samples: "
        f"block={samples['block_flush_end_to_end']} "
        f"pre_issue={samples['block_flush_to_ata_issue']} "
        f"ata={samples['ata_flush_issue_to_completion']} "
        f"flush_ext_issued={samples['ata_flush_ext_issued']} "
        f"block_failed={samples['block_flush_failed']} "
        f"ata_flush_failed={samples['ata_flush_failed']} "
        f"ata_commands_failed={samples['ata_commands_failed']}"
    )
    unmatched = result["unmatched"]
    print(
        "unmatched: "
        + " ".join(f"{key}={value}" for key, value in unmatched.items())
    )
    for name, values in result["latency_ms"].items():
        if values is None:
            print(f"{name} ms: no samples")
        else:
            print(
                f"{name} ms: "
                + " ".join(f"{key}={value}" for key, value in values.items())
            )
    print(f"acceptable: {not errors}")
    for error in errors:
        print(f"acceptance error: {error}")
    return int(args.strict and bool(errors))


if __name__ == "__main__":
    sys.exit(main())
