#!/usr/bin/env python3
"""Force Haswell DDI A to 4 lanes before i915 binds, then load i915.

Apple EFI on MacBookPro11,3 starts Linux with the mux on DIS, so Intel GOP
never sets DDI_A_4_LANES in DDI_BUF_CTL_A. i915 then treats PORT_A as 2-lane
(shared with PORT_E). Two-lane HBR cannot carry the panel's 337.75 MHz
2880x1800 mode, so mode_valid returns CLOCK_HIGH and DRM advertises 0 modes.

This helper sets bit 4 of MMIO 0x64000, then (re)loads i915. Run only on the
force_igd UKI path, before the display manager.
"""
from __future__ import annotations

import mmap
import os
import struct
import subprocess
import sys
import time

BAR = "/sys/bus/pci/devices/0000:00:02.0/resource0"
ENABLE = "/sys/bus/pci/devices/0000:00:02.0/enable"
HDMI_AUDIO = "0000:00:03.0"
DDI_BUF_CTL_A = 0x64000
DDI_A_4_LANES = 1 << 4


def log(msg: str) -> None:
    print(f"retinaforge-i915-ddi-4lanes: {msg}", flush=True)


def run(cmd: list[str], check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=check, text=True, capture_output=False)


def i915_loaded() -> bool:
    try:
        with open("/proc/modules", encoding="utf-8") as fh:
            return any(line.startswith("i915 ") for line in fh)
    except OSError:
        return False


def unbind_hdmi_audio() -> None:
    path = f"/sys/bus/pci/drivers/snd_hda_intel/unbind"
    if not os.path.exists(path):
        return
    try:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(HDMI_AUDIO)
        log(f"unbound snd_hda_intel from {HDMI_AUDIO}")
    except OSError as exc:
        log(f"unbind {HDMI_AUDIO}: {exc} (ok if already free)")


def drop_i915() -> None:
    if not i915_loaded():
        log("i915 not loaded")
        return
    unbind_hdmi_audio()
    log("removing i915")
    result = run(["timeout", "25", "modprobe", "-r", "i915"])
    if result.returncode != 0 or i915_loaded():
        log("ERROR: could not rmmod i915")
        sys.exit(1)
    time.sleep(0.5)


def enable_bar() -> None:
    if not os.path.exists(ENABLE):
        return
    try:
        with open(ENABLE, "r", encoding="utf-8") as fh:
            if fh.read().strip() == "1":
                return
        with open(ENABLE, "w", encoding="utf-8") as fh:
            fh.write("1")
        log("enabled PCI 0000:00:02.0")
    except OSError as exc:
        log(f"PCI enable: {exc}")


def poke_ddi_a_4_lanes() -> None:
    if not os.path.exists(BAR):
        log(f"ERROR: missing {BAR} (iGPU not enumerated)")
        sys.exit(1)
    enable_bar()
    fd = os.open(BAR, os.O_RDWR | os.O_SYNC)
    try:
        size = os.fstat(fd).st_size
        if size <= DDI_BUF_CTL_A + 4:
            size = DDI_BUF_CTL_A + 8
        mm = mmap.mmap(fd, size, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
        try:
            val = struct.unpack_from("<I", mm, DDI_BUF_CTL_A)[0]
            log(f"DDI_BUF_CTL_A before=0x{val:08x} 4lanes={bool(val & DDI_A_4_LANES)}")
            struct.pack_into("<I", mm, DDI_BUF_CTL_A, val | DDI_A_4_LANES)
            mm.flush()
            check = struct.unpack_from("<I", mm, DDI_BUF_CTL_A)[0]
            log(f"DDI_BUF_CTL_A after=0x{check:08x} 4lanes={bool(check & DDI_A_4_LANES)}")
            if not (check & DDI_A_4_LANES):
                log("ERROR: DDI_A_4_LANES did not stick")
                sys.exit(1)
        finally:
            mm.close()
    finally:
        os.close(fd)


def load_i915() -> None:
    log("modprobe i915 enable_dc=0")
    run(["modprobe", "i915", "enable_dc=0"], check=True)
    deadline = time.time() + 8
    while time.time() < deadline:
        if i915_loaded():
            break
        time.sleep(0.2)
    time.sleep(1.0)


def main() -> int:
    if os.geteuid() != 0:
        log("must run as root")
        return 1
    drop_i915()
    poke_ddi_a_4_lanes()
    load_i915()
    fb = "/sys/class/graphics/fb0/name"
    fb_name = "none"
    if os.path.exists(fb):
        fb_name = open(fb, encoding="utf-8").read().strip()
    log(f"fb0={fb_name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
