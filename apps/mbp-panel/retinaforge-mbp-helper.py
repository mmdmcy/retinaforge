#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Privileged helper for the MacBookPro11,3 RetinaForge tray panel.

Allowed writes: vga_switcheroo ON / OFF (power the unused GPU).
Refuses IGD/DIS mux hops — those black the lid on this indexed GMUX.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

SWITCH = Path("/sys/kernel/debug/vgaswitcheroo/switch")
FB_NAME = Path("/sys/class/graphics/fb0/name")
DMI_PRODUCT = Path("/sys/class/dmi/id/product_name")
SMC = Path("/sys/devices/platform/applesmc.768")
PCI_DIS = Path("/sys/bus/pci/devices/0000:01:00.0")
PCI_IGD = Path("/sys/bus/pci/devices/0000:00:02.0")
ALLOWED_PRODUCTS = {"MacBookPro11,3"}


def _read(path: Path, default: str = "") -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return default


def _read_millic(path: Path) -> float | None:
    raw = _read(path)
    if not raw.lstrip("-").isdigit():
        return None
    return int(raw) / 1000.0


def _parse_switcheroo(text: str) -> dict[str, str]:
    out = {"igd": "unknown", "dis": "unknown", "igd_sel": False, "dis_sel": False}
    for line in text.splitlines():
        parts = line.split(":")
        if len(parts) < 4:
            continue
        tag = parts[1]
        sel = parts[2].strip() == "+"
        pwr = parts[3].strip()
        if tag == "IGD":
            out["igd"] = pwr
            out["igd_sel"] = sel
        elif tag == "DIS":
            out["dis"] = pwr
            out["dis_sel"] = sel
    return out


def _edp_mode() -> str:
    drm = Path("/sys/class/drm")
    if not drm.is_dir():
        return ""
    for status in drm.glob("card*-eDP-*/status"):
        if _read(status) != "connected":
            continue
        modes = _read(status.parent / "modes")
        first = modes.splitlines()[0] if modes else ""
        return f"{status.parent.name} {first}".strip()
    return ""


def _cpu_temp() -> float | None:
    hwmon = Path("/sys/class/hwmon")
    if hwmon.is_dir():
        for name in hwmon.glob("hwmon*/name"):
            if _read(name) != "coretemp":
                continue
            pkg = name.parent / "temp1_input"
            t = _read_millic(pkg)
            if t is not None:
                return t
    t = _read_millic(Path("/sys/class/thermal/thermal_zone1/temp"))
    return t


def _dgpu_temp() -> float | None:
    hwmon = Path("/sys/class/hwmon")
    if not hwmon.is_dir():
        return None
    for name in hwmon.glob("hwmon*/name"):
        if _read(name) != "nouveau":
            continue
        return _read_millic(name.parent / "temp1_input")
    return None


def _fans() -> tuple[int | None, int | None]:
    left = _read(SMC / "fan1_input")
    right = _read(SMC / "fan2_input")
    def n(v: str) -> int | None:
        return int(v) if v.isdigit() else None
    return n(left), n(right)


def collect_status() -> dict:
    product = _read(DMI_PRODUCT) or "unknown"
    sw = _parse_switcheroo(_read(SWITCH))
    fb = _read(FB_NAME) or "none"
    intel_lid = "i915" in fb
    dis_on = sw["dis"].lower() in {"pwr", "dynpwr"}
    return {
        "ok": True,
        "product": product,
        "product_ok": product in ALLOWED_PRODUCTS,
        "fb": fb,
        "intel_lid": intel_lid,
        "edp": _edp_mode(),
        "igd": sw["igd"],
        "igd_sel": sw["igd_sel"],
        "dis": sw["dis"],
        "dis_sel": sw["dis_sel"],
        "dis_on": dis_on,
        "cpu_c": _cpu_temp(),
        "dgpu_c": _dgpu_temp(),
        "fan_l": _fans()[0],
        "fan_r": _fans()[1],
        "pci_dis_power": _read(PCI_DIS / "power/runtime_status") or "?",
        "mode": "cool" if intel_lid and not dis_on else ("awake" if intel_lid else "fault"),
    }


def power_unused(state: str) -> dict:
    if state not in {"ON", "OFF"}:
        return {"ok": False, "error": "only ON or OFF is allowed"}
    product = _read(DMI_PRODUCT) or "unknown"
    if product not in ALLOWED_PRODUCTS:
        return {
            "ok": False,
            "error": f"refusing GPU power writes on {product} (MacBookPro11,3 only)",
        }
    if not SWITCH.exists():
        return {"ok": False, "error": "vgaswitcheroo not available (debugfs / apple-gmux)"}
    try:
        SWITCH.write_text(state + "\n", encoding="utf-8")
    except OSError as exc:
        return {"ok": False, "error": str(exc)}
    return collect_status()


def main() -> int:
    if os.geteuid() != 0:
        print(json.dumps({"ok": False, "error": "helper must run as root (pkexec)"}))
        return 1
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "status":
        result = collect_status()
    elif cmd == "dis-off":
        result = power_unused("OFF")
    elif cmd == "dis-on":
        result = power_unused("ON")
    else:
        result = {
            "ok": False,
            "error": "unknown command (status|dis-off|dis-on). mux hops are refused.",
        }
    print(json.dumps(result, separators=(",", ":")))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
