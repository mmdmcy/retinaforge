#!/usr/bin/env python3
"""Classify in-kernel AHCI FLUSH_EXT register samples from appliance captures.

Tags are reused across flushes, so samples are paired chronologically as
issue -> timer* -> complete for the same tag.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

LINE_RE = re.compile(
    r"(?:\[ *(?P<ts>[0-9.]+)\] )?"
    r"mbp-ahci-flush-reg when=(?P<when>\w+) tag=(?P<tag>\d+) "
    r"age_ms=(?P<age>\d+) host_is=(?P<host_is>0x[0-9a-fA-F]+) "
    r"pxis=(?P<pxis>0x[0-9a-fA-F]+) pxci=(?P<pxci>0x[0-9a-fA-F]+) "
    r"pxsact=(?P<pxsact>0x[0-9a-fA-F]+) pxtfd=(?P<pxtfd>0x[0-9a-fA-F]+) "
    r"pxserr=(?P<pxserr>0x[0-9a-fA-F]+)"
)


def parse_lines(text: str) -> list[dict]:
    samples: list[dict] = []
    for line in text.splitlines():
        match = LINE_RE.search(line)
        if not match:
            continue
        tag = int(match.group("tag"))
        pxci = int(match.group("pxci"), 16)
        samples.append(
            {
                "ts": float(match.group("ts")) if match.group("ts") else None,
                "when": match.group("when"),
                "tag": tag,
                "age_ms": int(match.group("age")),
                "host_is": int(match.group("host_is"), 16),
                "pxis": int(match.group("pxis"), 16),
                "pxci": pxci,
                "pxsact": int(match.group("pxsact"), 16),
                "pxtfd": int(match.group("pxtfd"), 16),
                "pxserr": int(match.group("pxserr"), 16),
                "ci_bit": bool(pxci & (1 << tag)),
            }
        )
    return samples


def pair_flushes(samples: list[dict]) -> list[dict]:
    open_by_tag: dict[int, dict] = {}
    flushes: list[dict] = []
    for sample in samples:
        tag = sample["tag"]
        if sample["when"] == "issue":
            open_by_tag[tag] = {
                "tag": tag,
                "issue": sample,
                "timers": [],
            }
        elif sample["when"] == "timer":
            current = open_by_tag.get(tag)
            if current is not None:
                current["timers"].append(sample)
        elif sample["when"] == "complete":
            current = open_by_tag.pop(tag, None)
            if current is None:
                continue
            current["complete"] = sample
            current["complete_age_ms"] = sample["age_ms"]
            timers = current["timers"]
            if not timers:
                classification = "no_timer_sample"
            elif any(timer["ci_bit"] for timer in timers):
                classification = "ci_held"
            else:
                classification = "ci_cleared_early"
            current["classification"] = classification
            flushes.append(current)
    return flushes


def summarize(text: str, min_complete_age_ms: int = 100) -> dict:
    samples = parse_lines(text)
    flushes = pair_flushes(samples)
    long_flushes = [
        {
            "tag": flush["tag"],
            "complete_age_ms": flush["complete_age_ms"],
            "classification": flush["classification"],
            "timer_count": len(flush["timers"]),
            "timer_ci_bits": [timer["ci_bit"] for timer in flush["timers"]],
        }
        for flush in flushes
        if flush["complete_age_ms"] >= min_complete_age_ms
    ]
    classes = Counter(item["classification"] for item in long_flushes)
    if not long_flushes:
        verdict = "no_long_flushes"
    elif set(classes) == {"ci_held"}:
        verdict = "ci_held"
    elif set(classes) == {"ci_cleared_early"}:
        verdict = "ci_cleared_early"
    else:
        verdict = "mixed"

    return {
        "sample_count": len(samples),
        "flush_count": len(flushes),
        "long_flush_count": len(long_flushes),
        "long_class_counts": dict(classes),
        "verdict": verdict,
        "flushes": long_flushes,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "path",
        type=Path,
        help="ahci-flush-reg.txt or controller-state.txt containing mbp-ahci-flush-reg lines",
    )
    parser.add_argument(
        "--min-complete-age-ms",
        type=int,
        default=100,
        help="only classify flushes whose complete age is at least this long",
    )
    parser.add_argument("--json", action="store_true", help="print JSON")
    args = parser.parse_args()
    result = summarize(args.path.read_text(errors="replace"), args.min_complete_age_ms)
    if args.json:
        json.dump(result, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        print(
            f"samples={result['sample_count']} "
            f"flushes={result['flush_count']} "
            f"long_flushes={result['long_flush_count']} "
            f"verdict={result['verdict']}"
        )
        if result["long_class_counts"]:
            print(f"long_classes={result['long_class_counts']}")
        for item in result["flushes"][:8]:
            print(
                f"  tag={item['tag']} age_ms={item['complete_age_ms']} "
                f"class={item['classification']} timers={item['timer_count']}"
            )
        if len(result["flushes"]) > 8:
            print(f"  ... {len(result['flushes']) - 8} more")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
