#!/usr/bin/env python3
"""Build a Darwin-versus-Linux flush/command-pattern difference table."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SUMMARY_RE = re.compile(
    r"^summary,os=darwin,mode=(?P<mode>[^,]+),count=(?P<count>\d+),"
    r"mean_sync_ms=(?P<mean>[0-9.]+),median_sync_ms=(?P<median>[0-9.]+),"
    r"p95_sync_ms=(?P<p95>[0-9.]+),max_sync_ms=(?P<max>[0-9.]+),"
    r"long_sync_count=(?P<long>\d+),first_long_index=(?P<first>[^,]+),"
    r"wall_ms=(?P<wall>[0-9.]+),syncs_per_s=(?P<rate>[0-9.]+)$"
)


def parse_darwin(path: Path) -> dict:
    modes: dict[str, dict] = {}
    config: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("config,os=darwin,"):
            for part in line.split(",")[1:]:
                if "=" in part:
                    key, value = part.split("=", 1)
                    config[key] = value
            continue
        match = SUMMARY_RE.match(line)
        if not match:
            continue
        modes[match["mode"]] = {
            "count": int(match["count"]),
            "mean_sync_ms": float(match["mean"]),
            "median_sync_ms": float(match["median"]),
            "p95_sync_ms": float(match["p95"]),
            "max_sync_ms": float(match["max"]),
            "long_sync_count": int(match["long"]),
            "first_long_index": match["first"],
            "wall_ms": float(match["wall"]),
            "syncs_per_s": float(match["rate"]),
        }
    return {"os": "darwin", "config": config, "modes": modes}


def load_linux(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("os") != "linux":
        raise SystemExit(f"{path} is not a linux extract-flush-pattern JSON")
    return data


def compare(linux: dict, darwin: dict) -> dict:
    sustained = darwin["modes"].get("sustained-F_FULLFSYNC")
    isolated = darwin["modes"].get("isolated-F_FULLFSYNC")
    flush_only = darwin["modes"].get("flush-only-F_FULLFSYNC")
    linux_flush = linux.get("flush_completion_ms") or {}
    linux_long = linux.get("long_flush_completion_ms") or {}

    rows = [
        {
            "metric": "strict_sync_median_ms",
            "linux": linux_flush.get("p50"),
            "darwin_isolated": isolated["median_sync_ms"] if isolated else None,
            "darwin_sustained": sustained["median_sync_ms"] if sustained else None,
            "darwin_flush_only": flush_only["median_sync_ms"] if flush_only else None,
        },
        {
            "metric": "strict_sync_p95_ms",
            "linux": linux_flush.get("p95"),
            "darwin_isolated": isolated["p95_sync_ms"] if isolated else None,
            "darwin_sustained": sustained["p95_sync_ms"] if sustained else None,
            "darwin_flush_only": flush_only["p95_sync_ms"] if flush_only else None,
        },
        {
            "metric": "strict_sync_max_ms",
            "linux": linux_flush.get("max"),
            "darwin_isolated": isolated["max_sync_ms"] if isolated else None,
            "darwin_sustained": sustained["max_sync_ms"] if sustained else None,
            "darwin_flush_only": flush_only["max_sync_ms"] if flush_only else None,
        },
        {
            "metric": "long_sync_count_ge_100ms",
            "linux": linux.get("long_flush_count"),
            "darwin_isolated": isolated["long_sync_count"] if isolated else None,
            "darwin_sustained": sustained["long_sync_count"] if sustained else None,
            "darwin_flush_only": flush_only["long_sync_count"] if flush_only else None,
        },
        {
            "metric": "sync_or_flush_count",
            "linux": linux.get("flush_ext_count"),
            "darwin_isolated": isolated["count"] if isolated else None,
            "darwin_sustained": sustained["count"] if sustained else None,
            "darwin_flush_only": flush_only["count"] if flush_only else None,
        },
        {
            "metric": "fpdma_writes_in_window",
            "linux": linux.get("fpdma_write_count"),
            "darwin_isolated": None,
            "darwin_sustained": None,
            "darwin_flush_only": None,
            "note": "Darwin userspace probe cannot see ATA opcodes",
        },
        {
            "metric": "pxci_long_flush_verdict",
            "linux": (linux.get("flush_reg") or {}).get("verdict"),
            "darwin_isolated": None,
            "darwin_sustained": None,
            "darwin_flush_only": None,
            "note": "Darwin AHCI PxCI not sampled by this harness",
        },
        {
            "metric": "long_flush_p50_ms",
            "linux": linux_long.get("p50"),
            "darwin_isolated": None,
            "darwin_sustained": None,
            "darwin_flush_only": None,
        },
    ]

    hypotheses = []
    if sustained and sustained["long_sync_count"] == 0 and linux.get("long_flush_count", 0) > 0:
        hypotheses.append(
            "darwin_stays_fast_under_sustained_fullfsync_while_linux_has_long_flushes"
        )
    if sustained and sustained["long_sync_count"] > 0:
        hypotheses.append(
            "darwin_also_enters_slow_mode_under_sustained_fullfsync_compare_entry_point"
        )
    if (
        flush_only
        and flush_only["long_sync_count"] == 0
        and sustained
        and sustained["long_sync_count"] > 0
    ):
        hypotheses.append(
            "darwin_slow_mode_needs_intervening_writes_not_flush_alone"
        )
    if (
        flush_only
        and flush_only["max_sync_ms"] < 50
        and linux.get("long_flush_count", 0) > 0
    ):
        hypotheses.append(
            "linux_slow_path_likely_depends_on_write_plus_flush_mix_or_fs_pattern"
        )

    return {
        "linux_source": linux.get("source"),
        "darwin_config": darwin.get("config"),
        "rows": rows,
        "hypotheses": hypotheses,
        "next_experiment": (
            hypotheses[0]
            if hypotheses
            else "collect_darwin_sustained_probe_output_and_rerun_compare"
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--linux-json",
        type=Path,
        required=True,
        help="output of extract-flush-pattern.py --json",
    )
    parser.add_argument(
        "--darwin-log",
        type=Path,
        required=True,
        help="stdout capture from macos-flush-pattern-probe",
    )
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    result = compare(load_linux(args.linux_json), parse_darwin(args.darwin_log))
    if args.json:
        json.dump(result, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    else:
        print("metric\tlinux\tdarwin_isolated\tdarwin_sustained\tdarwin_flush_only")
        for row in result["rows"]:
            print(
                f"{row['metric']}\t{row.get('linux')}\t{row.get('darwin_isolated')}\t"
                f"{row.get('darwin_sustained')}\t{row.get('darwin_flush_only')}"
            )
        print("hypotheses:")
        for item in result["hypotheses"]:
            print(f"  - {item}")
        print(f"next_experiment: {result['next_experiment']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
