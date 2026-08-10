#!/usr/bin/env python3
"""Write Apple GPU EFI variables for Intel-first boot prep."""

from __future__ import annotations

import os
import subprocess
import sys

ATTR = bytes([0x07, 0x00, 0x00, 0x80])
POLICY_VAR = "/sys/firmware/efi/efivars/gpu-policy-7c436110-ab2a-4bbb-a880-fe41995c9f82"
PREFS_VAR = "/sys/firmware/efi/efivars/gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9"


def write_efivar(path: str, payload: bytes) -> None:
    data = ATTR + payload
    try:
        subprocess.run(["chattr", "-i", path], check=False, capture_output=True)
    except OSError:
        pass
    with open(path, "wb") as handle:
        handle.write(data)
    try:
        subprocess.run(["chattr", "+i", path], check=False, capture_output=True)
    except OSError:
        pass


def main() -> int:
    if os.geteuid() != 0:
        print("run as root", file=sys.stderr)
        return 1

    write_efivar(POLICY_VAR, b"\x01")
    print("gpu-policy -> Intel (%01)")
    try:
        write_efivar(PREFS_VAR, b"\x01\x00\x00\x00")
        print("gpu-power-prefs -> %01%00%00%00")
    except OSError as exc:
        print(f"warn: gpu-power-prefs write failed: {exc}")

    for path in (POLICY_VAR, PREFS_VAR):
        if os.path.exists(path):
            blob = open(path, "rb").read()
            print(f"{os.path.basename(path)} readback: {blob.hex()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
