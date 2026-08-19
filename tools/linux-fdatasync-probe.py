#!/usr/bin/env python3
"""Userspace 1 MiB write + fdatasync/fsync probe.

Use a directory on the real root/home volume, not tmpfs /tmp.
See docs/source-notes/2026-08-19-omarchy-luks-btrfs-sync.md.
"""
from __future__ import annotations

import os
import statistics
import sys
import time

DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~")
N = int(sys.argv[2]) if len(sys.argv) > 2 else 12
SIZE = 1024 * 1024
payload = os.urandom(SIZE)
path = os.path.join(DIR, ".retinaforge-sync-probe.bin")


def pct(xs: list[float], p: float) -> float:
    if not xs:
        return float("nan")
    s = sorted(xs)
    i = min(len(s) - 1, max(0, int(round((p / 100.0) * (len(s) - 1)))))
    return s[i]


def run(kind: str) -> tuple[list[float], list[float]]:
    writes: list[float] = []
    syncs: list[float] = []
    with open(path, "wb", buffering=0) as f:
        fd = f.fileno()
        for _ in range(N):
            os.lseek(fd, 0, os.SEEK_SET)
            t0 = time.perf_counter()
            os.write(fd, payload)
            t1 = time.perf_counter()
            if kind == "fdatasync":
                os.fdatasync(fd)
            else:
                os.fsync(fd)
            t2 = time.perf_counter()
            writes.append((t1 - t0) * 1000)
            syncs.append((t2 - t1) * 1000)
    return writes, syncs


def report(label: str, writes: list[float], syncs: list[float]) -> None:
    long_n = sum(1 for x in syncs if x >= 100)
    print(f"=== {label}  n={len(syncs)}  1 MiB  dir={DIR} ===")
    print(
        f"write  ms  p50={statistics.median(writes):.3f}  "
        f"p95={pct(writes, 95):.3f}  max={max(writes):.3f}"
    )
    print(
        f"sync   ms  p50={statistics.median(syncs):.3f}  "
        f"p95={pct(syncs, 95):.3f}  max={max(syncs):.3f}  "
        f"long>=100ms={long_n}"
    )
    print("sync samples ms:", " ".join(f"{x:.1f}" for x in syncs))


def main() -> None:
    print("probe_dir", DIR)
    for kind in ("fdatasync", "fsync"):
        w, s = run(kind)
        report(kind, w, s)
    os.remove(path)


if __name__ == "__main__":
    main()
