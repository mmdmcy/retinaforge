#!/usr/bin/env bash
# Bounded durable-write latency probe for the Apple AHCI investigation.
#
# It creates a temporary file only under a directory on the root filesystem,
# measures fdatasync() latency, and removes the data before exiting. Optional
# ftrace capture needs root and writes only to the caller-supplied path.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run-latency-probe.sh --yes [options]

Options:
  --directory PATH     Temporary-file parent directory (default: /var/tmp)
  --size-mib N         Total bytes to write in MiB, 1..128 (default: 16)
  --chunk-kib N        Write size in KiB, 4..1024 (default: 1024)
  --sync-every N       Call fdatasync after N chunks, 1..64 (default: 1)
  --trace-out PATH     Save block issue/complete ftrace output; requires root
  --yes                Required acknowledgement of the bounded write
  -h, --help           Show this help

The test refuses a directory outside the root filesystem and removes its test
data on exit. Trace output can contain process names and must stay untracked.
EOF
}

test_parent=/var/tmp
size_mib=16
chunk_kib=1024
sync_every=1
trace_out=
confirmed=0

while (($#)); do
  case "$1" in
    --directory)
      test_parent=${2:?missing path after --directory}
      shift 2
      ;;
    --size-mib)
      size_mib=${2:?missing value after --size-mib}
      shift 2
      ;;
    --chunk-kib)
      chunk_kib=${2:?missing value after --chunk-kib}
      shift 2
      ;;
    --sync-every)
      sync_every=${2:?missing value after --sync-every}
      shift 2
      ;;
    --trace-out)
      trace_out=${2:?missing path after --trace-out}
      shift 2
      ;;
    --yes)
      confirmed=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

is_integer() {
  [[ $1 =~ ^[0-9]+$ ]]
}

for value in "$size_mib" "$chunk_kib" "$sync_every"; do
  if ! is_integer "$value"; then
    printf 'Numeric options must be positive integers.\n' >&2
    exit 2
  fi
done

if ((size_mib < 1 || size_mib > 128)); then
  printf '--size-mib must be between 1 and 128.\n' >&2
  exit 2
fi
if ((chunk_kib < 4 || chunk_kib > 1024)); then
  printf '--chunk-kib must be between 4 and 1024.\n' >&2
  exit 2
fi
if ((sync_every < 1 || sync_every > 64)); then
  printf '--sync-every must be between 1 and 64.\n' >&2
  exit 2
fi
if ((confirmed != 1)); then
  printf 'Refusing to write test data without --yes.\n' >&2
  exit 2
fi
if [[ ! -d $test_parent ]]; then
  printf 'Directory does not exist: %s\n' "$test_parent" >&2
  exit 2
fi

root_source=$(findmnt -n -o SOURCE -T /)
test_source=$(findmnt -n -o SOURCE -T "$test_parent")
if [[ -z $root_source || $root_source != "$test_source" ]]; then
  printf 'Refusing: %s is not on the root filesystem.\n' "$test_parent" >&2
  exit 2
fi

if [[ -n $trace_out && $EUID -ne 0 ]]; then
  printf '--trace-out requires running this script as root.\n' >&2
  exit 2
fi

workdir=$(mktemp -d "$test_parent/apple-ahci-latency.XXXXXX")
data_file="$workdir/durable-write.bin"
trace_root=/sys/kernel/tracing
trace_active=0
old_tracing_on=
old_issue=
old_complete=

restore_trace() {
  if ((trace_active)); then
    printf '0' > "$trace_root/events/block/block_rq_issue/enable" || true
    printf '0' > "$trace_root/events/block/block_rq_complete/enable" || true
    printf '%s' "$old_issue" > "$trace_root/events/block/block_rq_issue/enable" || true
    printf '%s' "$old_complete" > "$trace_root/events/block/block_rq_complete/enable" || true
    printf '%s' "$old_tracing_on" > "$trace_root/tracing_on" || true
  fi
}

cleanup() {
  local rc=$?
  restore_trace
  rm -rf "$workdir"
  trap - EXIT
  exit "$rc"
}
trap cleanup EXIT INT TERM

if [[ -n $trace_out ]]; then
  if [[ ! -d $trace_root || ! -w $trace_root/tracing_on ]]; then
    printf 'tracefs is not available at %s.\n' "$trace_root" >&2
    exit 1
  fi
  if [[ -e $trace_out ]]; then
    printf 'Refusing to overwrite trace output: %s\n' "$trace_out" >&2
    exit 2
  fi
  mkdir -p "$(dirname "$trace_out")"
  old_tracing_on=$(<"$trace_root/tracing_on")
  old_issue=$(<"$trace_root/events/block/block_rq_issue/enable")
  old_complete=$(<"$trace_root/events/block/block_rq_complete/enable")
  printf '0' > "$trace_root/tracing_on"
  : > "$trace_root/trace"
  printf '1' > "$trace_root/events/block/block_rq_issue/enable"
  printf '1' > "$trace_root/events/block/block_rq_complete/enable"
  printf '1' > "$trace_root/tracing_on"
  trace_active=1
fi

printf '## probe configuration\n'
printf 'size_mib=%s chunk_kib=%s sync_every=%s\n' \
  "$size_mib" "$chunk_kib" "$sync_every"
printf '## io pressure before\n'
cat /proc/pressure/io
printf '## fdatasync latency summary\n'

python3 - "$data_file" "$size_mib" "$chunk_kib" "$sync_every" <<'PY'
import json
import math
import os
import sys
import time

path = sys.argv[1]
size_bytes = int(sys.argv[2]) * 1024 * 1024
chunk_bytes = int(sys.argv[3]) * 1024
sync_every = int(sys.argv[4])

payload = os.urandom(chunk_bytes)
latencies_ms = []
bytes_written = 0
chunks_since_sync = 0
started = time.monotonic_ns()
fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
try:
    while bytes_written < size_bytes:
        remaining = size_bytes - bytes_written
        piece = payload if remaining >= chunk_bytes else payload[:remaining]
        os.write(fd, piece)
        bytes_written += len(piece)
        chunks_since_sync += 1
        if chunks_since_sync >= sync_every or bytes_written == size_bytes:
            sync_started = time.monotonic_ns()
            os.fdatasync(fd)
            latencies_ms.append((time.monotonic_ns() - sync_started) / 1_000_000)
            chunks_since_sync = 0
finally:
    os.close(fd)

ordered = sorted(latencies_ms)
def percentile(percent):
    if not ordered:
        return None
    rank = max(0, math.ceil((percent / 100) * len(ordered)) - 1)
    return ordered[rank]

elapsed_s = (time.monotonic_ns() - started) / 1_000_000_000
result = {
    "bytes_written": bytes_written,
    "sync_samples": len(latencies_ms),
    "elapsed_seconds": round(elapsed_s, 3),
    "throughput_mib_per_second": round((bytes_written / 1024 / 1024) / elapsed_s, 3),
    "latency_ms": {
        "p50": round(percentile(50), 3),
        "p95": round(percentile(95), 3),
        "p99": round(percentile(99), 3),
        "max": round(max(latencies_ms), 3),
    },
    "samples_ms": [round(value, 3) for value in latencies_ms],
}
print(json.dumps(result, sort_keys=True))
PY

if ((trace_active)); then
  printf '0' > "$trace_root/tracing_on"
  printf '0' > "$trace_root/events/block/block_rq_issue/enable"
  printf '0' > "$trace_root/events/block/block_rq_complete/enable"
  cat "$trace_root/trace" > "$trace_out"
  printf 'trace_output=%s\n' "$trace_out"
fi

printf '## io pressure after\n'
cat /proc/pressure/io
