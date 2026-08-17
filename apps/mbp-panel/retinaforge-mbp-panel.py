#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""RetinaForge tray plate for MacBookPro11,3 — Intel lid + GT 750M power.

Left-click the tray jewel to open. Sleep/Wake only power the unused GPU.
They do not flip the panel mux.
"""
from __future__ import annotations

import faulthandler
import json
import os
import shlex
import shutil
import subprocess
import sys
import traceback
from pathlib import Path

try:
    from PyQt6.QtCore import QPoint, QProcess, QProcessEnvironment, QRectF, QSettings, Qt, QTimer
    from PyQt6.QtGui import (
        QAction,
        QColor,
        QCursor,
        QFont,
        QGuiApplication,
        QIcon,
        QLinearGradient,
        QPainter,
        QPainterPath,
        QPen,
        QPixmap,
        QRadialGradient,
    )
    from PyQt6.QtWidgets import (
        QApplication,
        QCompleter,
        QFileDialog,
        QFrame,
        QHBoxLayout,
        QLabel,
        QLineEdit,
        QMenu,
        QProgressBar,
        QPushButton,
        QScrollArea,
        QStackedWidget,
        QSystemTrayIcon,
        QVBoxLayout,
        QWidget,
    )
except ImportError:
    from PySide6.QtCore import QPoint, QProcess, QProcessEnvironment, QRectF, QSettings, Qt, QTimer
    from PySide6.QtGui import (
        QAction,
        QColor,
        QCursor,
        QFont,
        QGuiApplication,
        QIcon,
        QLinearGradient,
        QPainter,
        QPainterPath,
        QPen,
        QPixmap,
        QRadialGradient,
    )
    from PySide6.QtWidgets import (
        QApplication,
        QCompleter,
        QFileDialog,
        QFrame,
        QHBoxLayout,
        QLabel,
        QLineEdit,
        QMenu,
        QProgressBar,
        QPushButton,
        QScrollArea,
        QStackedWidget,
        QSystemTrayIcon,
        QVBoxLayout,
        QWidget,
    )

HELPER_CANDIDATES = [
    Path("/usr/local/libexec/retinaforge-mbp-helper"),
    Path("/usr/libexec/retinaforge-mbp-helper"),
    Path(__file__).resolve().parent / "retinaforge-mbp-helper.py",
]

INK = "#f3ead8"
MUTED = "#9a8c78"
IRIS = "#86c4a4"
KEPLER = "#e2a056"
FAULT = "#d26452"
COOL = "#7eb4c8"
PLATE_TOP = QColor("#3a342b")
PLATE_BOT = QColor("#1c1813")


def _pick_font(families: tuple[str, ...], point: int, bold: bool = False) -> QFont:
    chosen = families[-1]
    for family in families:
        probe = QFont(family)
        if probe.exactMatch():
            chosen = family
            break
    font = QFont(chosen)
    font.setPixelSize(point)
    font.setWeight(QFont.Weight.DemiBold if bold else QFont.Weight.Medium)
    return font


def _sans(point: int, bold: bool = False) -> QFont:
    font = _pick_font(("IBM Plex Sans", "Source Sans 3", "Noto Sans", "DejaVu Sans"), point, bold)
    font.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, 0.35)
    return font


def _mono(point: int) -> QFont:
    return _pick_font(("IBM Plex Mono", "Source Code Pro", "DejaVu Sans Mono"), point)


def helper_path() -> Path:
    for path in HELPER_CANDIDATES:
        if path.exists():
            return path
    return HELPER_CANDIDATES[-1]


def load_prime_history() -> list[str]:
    raw = QSettings("RetinaForge", "mbp-plate").value("prime_history", [])
    if isinstance(raw, str):
        return [raw] if raw else []
    if not raw:
        return []
    return [str(item) for item in raw]


def save_prime_history(entries: list[str]) -> None:
    QSettings("RetinaForge", "mbp-plate").setValue("prime_history", entries[:12])


def desktop_exec_line(path: Path) -> str | None:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    for line in text.splitlines():
        if line.startswith("Exec="):
            try:
                parts = shlex.split(line[5:])
            except ValueError:
                return None
            cleaned = [part for part in parts if not part.startswith("%")]
            return " ".join(cleaned) if cleaned else None
    return None


def run_helper(cmd: str) -> dict:
    helper = helper_path()
    installed = helper in HELPER_CANDIDATES[:2]
    attempts: list[list[str]] = []
    if os.geteuid() == 0:
        attempts.append([str(helper), cmd])
    else:
        if shutil.which("sudo"):
            attempts.append(["sudo", "-n", str(helper), cmd])
        if installed and shutil.which("pkexec"):
            attempts.append(["pkexec", str(helper), cmd])
        if not attempts:
            attempts.append([str(helper), cmd])
    last = {"ok": False, "error": "helper not invoked"}
    for argv in attempts:
        try:
            proc = subprocess.run(argv, check=False, capture_output=True, text=True, timeout=20)
        except (OSError, subprocess.TimeoutExpired) as exc:
            last = {"ok": False, "error": str(exc)}
            continue
        raw = (proc.stdout or "").strip() or (proc.stderr or "").strip()
        if not raw:
            last = {"ok": False, "error": f"helper empty (exit {proc.returncode})"}
            continue
        parsed = None
        for line in reversed(raw.splitlines()):
            line = line.strip()
            if line.startswith("{"):
                try:
                    parsed = json.loads(line)
                    break
                except json.JSONDecodeError:
                    break
        if parsed is not None:
            return parsed
        last = {"ok": False, "error": raw[:240]}
    return last


def lamp_color(status: dict) -> QColor:
    if not status.get("ok"):
        return QColor(FAULT)
    mode = status.get("mode")
    if mode == "cool":
        return QColor(IRIS)
    if mode == "awake":
        return QColor(KEPLER)
    return QColor(FAULT)


def make_tray_icon(color: QColor, size: int = 64) -> QIcon:
    pixmap = QPixmap(size, size)
    pixmap.fill(Qt.GlobalColor.transparent)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    plate = QRectF(3, 3, size - 6, size - 6)
    path = QPainterPath()
    path.addRoundedRect(plate, 11, 11)
    gradient = QLinearGradient(plate.topLeft(), plate.bottomRight())
    gradient.setColorAt(0.0, PLATE_TOP)
    gradient.setColorAt(1.0, PLATE_BOT)
    painter.fillPath(path, gradient)
    painter.setPen(QPen(QColor("#6a5f52"), 1.2))
    painter.drawPath(path)
    lamp = QRectF(size * 0.30, size * 0.30, size * 0.40, size * 0.40)
    glow = QRadialGradient(lamp.center(), lamp.width())
    glow_color = QColor(color)
    glow_color.setAlpha(120)
    glow.setColorAt(0.0, color)
    glow.setColorAt(0.55, glow_color)
    glow.setColorAt(1.0, QColor(0, 0, 0, 0))
    painter.setPen(Qt.PenStyle.NoPen)
    painter.setBrush(glow)
    painter.drawEllipse(lamp.adjusted(-6, -6, 6, 6))
    painter.setBrush(color)
    painter.drawEllipse(lamp)
    painter.setPen(QPen(QColor(255, 255, 255, 80), 1.0))
    painter.drawArc(lamp.adjusted(3, 3, -3, -3), 40 * 16, 80 * 16)
    painter.end()
    return QIcon(pixmap)


def _help_block(title: str, body: str, accent: str = IRIS) -> QWidget:
    box = QWidget()
    lay = QVBoxLayout(box)
    lay.setContentsMargins(0, 0, 0, 10)
    lay.setSpacing(3)
    head = QLabel(title)
    head.setFont(_sans(10, True))
    head.setStyleSheet(f"color: {accent}; letter-spacing: 0.8px;")
    head.setWordWrap(True)
    text = QLabel(body)
    text.setFont(_sans(12))
    text.setStyleSheet(f"color: {INK};")
    text.setWordWrap(True)
    text.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
    lay.addWidget(head)
    lay.addWidget(text)
    return box


class Meter(QWidget):
    def __init__(self, caption: str, maximum: float, parent=None):
        super().__init__(parent)
        self.maximum = max(1.0, maximum)
        row = QHBoxLayout()
        row.setContentsMargins(0, 0, 0, 0)
        self.caption = QLabel(caption)
        self.caption.setFont(_sans(10, True))
        self.caption.setStyleSheet(f"color: {MUTED};")
        self.reading = QLabel("—")
        self.reading.setFont(_mono(15))
        self.reading.setStyleSheet(f"color: {INK};")
        self.reading.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
        row.addWidget(self.caption)
        row.addWidget(self.reading, 1)
        self.bar = QProgressBar()
        self.bar.setRange(0, 1000)
        self.bar.setValue(0)
        self.bar.setTextVisible(False)
        self.bar.setFixedHeight(8)
        self._set_bar(COOL)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(0, 2, 0, 2)
        lay.setSpacing(4)
        lay.addLayout(row)
        lay.addWidget(self.bar)

    def _set_bar(self, accent: str) -> None:
        self.bar.setStyleSheet(
            "QProgressBar { background: #14110d; border: 0; border-radius: 4px; }"
            f"QProgressBar::chunk {{ background: {accent}; border-radius: 4px; }}"
        )

    def set_reading(self, value: float | None, label: str, accent: str) -> None:
        self.reading.setText(label)
        self._set_bar(accent)
        if value is None:
            self.bar.setValue(0)
            return
        self.bar.setValue(int(max(0.0, min(1.0, value / self.maximum)) * 1000))


class Plate(QWidget):
    def __init__(self, controller: "Controller"):
        super().__init__(None, Qt.WindowType.Tool | Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint)
        self.controller = controller
        self.setWindowTitle("RetinaForge plate")
        self.setFixedSize(408, 596)
        self.setObjectName("plate")
        self.setStyleSheet(
            f"""
            QWidget#plate {{
                background: qlineargradient(x1:0, y1:0, x2:1, y2:1,
                    stop:0 #3a342b, stop:1 #1c1813);
                color: {INK};
                border: 1px solid #6d6256;
            }}
            QLabel {{ background: transparent; }}
            QScrollArea {{ background: transparent; border: 0; }}
            QScrollBar:vertical {{
                background: #14110d; width: 8px; margin: 0; border: 0;
            }}
            QScrollBar::handle:vertical {{
                background: #5a5044; min-height: 24px; border-radius: 4px;
            }}
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{
                height: 0;
            }}
            """
        )

        lay = QVBoxLayout(self)
        lay.setContentsMargins(24, 22, 24, 20)
        lay.setSpacing(10)

        kick = QHBoxLayout()
        kicker = QLabel("RETINAFORGE   MacBookPro11,3")
        kicker.setFont(_sans(10, True))
        kicker.setStyleSheet(f"color: {MUTED}; letter-spacing: 1.6px;")
        self.help_btn = QPushButton("?")
        self.help_btn.setFixedSize(26, 26)
        self.help_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.help_btn.setToolTip("How this plate works")
        self.help_btn.setFont(_sans(14, True))
        self.help_btn.setStyleSheet(
            f"QPushButton {{ background: #14110d; color: {INK}; border: 1px solid #6d6256;"
            " border-radius: 13px; padding: 0; }"
            f"QPushButton:hover {{ border-color: {IRIS}; color: {IRIS}; }}"
        )
        kick.addWidget(kicker, 1)
        kick.addWidget(self.help_btn, 0, Qt.AlignmentFlag.AlignVCenter)
        lay.addLayout(kick)

        head = QHBoxLayout()
        self.title = QLabel("Lid on Iris Pro")
        self.title.setFont(_sans(21, True))
        self.title.setStyleSheet(f"color: {INK};")
        self.badge = QLabel("COOL")
        self.badge.setFont(_sans(11, True))
        self.badge.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.badge.setFixedSize(78, 26)
        head.addWidget(self.title, 1)
        head.addWidget(self.badge, 0, Qt.AlignmentFlag.AlignVCenter)
        lay.addLayout(head)

        self.subtitle = QLabel("2880×1800  ·  i915drmfb")
        self.subtitle.setFont(_mono(12))
        self.subtitle.setStyleSheet(f"color: {MUTED};")
        lay.addWidget(self.subtitle)

        rule = QWidget()
        rule.setFixedHeight(1)
        rule.setStyleSheet("background: #4a4338;")
        lay.addWidget(rule)

        self.stack = QStackedWidget()
        lay.addWidget(self.stack, 1)

        status = QWidget()
        status_lay = QVBoxLayout(status)
        status_lay.setContentsMargins(0, 0, 0, 0)
        status_lay.setSpacing(10)

        self.cpu = Meter("PACKAGE", 100)
        self.gpu = Meter("GT 750M", 105)
        self.fans = Meter("FANS", 6200)
        status_lay.addWidget(self.cpu)
        status_lay.addWidget(self.gpu)
        status_lay.addWidget(self.fans)

        self.note = QLabel("Wake the 750M only for prime-run OpenGL. Sleep it at idle.")
        self.note.setWordWrap(True)
        self.note.setFont(_sans(12))
        self.note.setStyleSheet(f"color: {MUTED};")
        status_lay.addWidget(self.note)

        btns = QHBoxLayout()
        btns.setSpacing(10)
        self.sleep_btn = QPushButton("Sleep 750M")
        self.wake_btn = QPushButton("Wake 750M")
        for button, fill in ((self.sleep_btn, IRIS), (self.wake_btn, KEPLER)):
            button.setCursor(Qt.CursorShape.PointingHandCursor)
            button.setFixedHeight(38)
            button.setFont(_sans(13, True))
            button.setStyleSheet(
                f"QPushButton {{ background: {fill}; color: #1a1611; border: 0;"
                " border-radius: 7px; padding: 0 14px; }"
                "QPushButton:disabled { background: #3a342c; color: #7a7166; }"
            )
            btns.addWidget(button)
        status_lay.addLayout(btns)

        run_row = QHBoxLayout()
        run_row.setSpacing(8)
        self.cmd_edit = QLineEdit()
        self.cmd_edit.setPlaceholderText("glxgears   or   steam")
        self.cmd_edit.setFont(_mono(12))
        self.cmd_edit.setFixedHeight(34)
        self.cmd_edit.setStyleSheet(
            f"QLineEdit {{ background: #14110d; color: {INK}; border: 1px solid #5a5044;"
            " border-radius: 7px; padding: 0 10px; selection-background-color: #4a4338; }}"
        )
        self.browse_btn = QPushButton("…")
        self.browse_btn.setFixedSize(34, 34)
        self.browse_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.browse_btn.setToolTip("Browse to a binary or .desktop")
        self.browse_btn.setFont(_sans(14, True))
        self.browse_btn.setStyleSheet(
            f"QPushButton {{ background: #14110d; color: {INK}; border: 1px solid #5a5044;"
            " border-radius: 7px; }}"
        )
        run_row.addWidget(self.cmd_edit, 1)
        run_row.addWidget(self.browse_btn)
        status_lay.addLayout(run_row)

        self.run_btn = QPushButton("Run on 750M")
        self.run_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.run_btn.setFixedHeight(36)
        self.run_btn.setFont(_sans(13, True))
        self.run_btn.setToolTip("Wake the 750M if needed, then DRI_PRIME=1")
        self.run_btn.setStyleSheet(
            f"QPushButton {{ background: {KEPLER}; color: #1a1611; border: 0;"
            " border-radius: 7px; }}"
            "QPushButton:disabled { background: #3a342c; color: #7a7166; }"
        )
        status_lay.addWidget(self.run_btn)
        self._prime_history = load_prime_history()
        self._completer = QCompleter(self._prime_history)
        self._completer.setCaseSensitivity(Qt.CaseSensitivity.CaseInsensitive)
        self.cmd_edit.setCompleter(self._completer)
        if self._prime_history:
            self.cmd_edit.setText(self._prime_history[0])

        self.mux = QLabel("mux —")
        self.mux.setFont(_mono(11))
        self.mux.setStyleSheet(f"color: {MUTED};")
        status_lay.addWidget(self.mux)

        self.err = QLabel("")
        self.err.setWordWrap(True)
        self.err.setFont(_sans(11))
        self.err.setStyleSheet(f"color: {FAULT};")
        status_lay.addWidget(self.err)
        status_lay.addStretch(1)

        self.stack.addWidget(status)
        self.stack.addWidget(self._build_help())

        self.sleep_btn.clicked.connect(lambda: self.controller.act("dis-off"))
        self.wake_btn.clicked.connect(lambda: self.controller.act("dis-on"))
        self.help_btn.clicked.connect(self.toggle_help)
        self.browse_btn.clicked.connect(self.browse_command)
        self.run_btn.clicked.connect(lambda: self.controller.launch_on_750m())
        self.cmd_edit.returnPressed.connect(lambda: self.controller.launch_on_750m())

    def _build_help(self) -> QWidget:
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        inner = QWidget()
        inner_lay = QVBoxLayout(inner)
        inner_lay.setContentsMargins(0, 4, 8, 8)
        inner_lay.setSpacing(2)

        self.now_label = QLabel("")
        self.now_label.setWordWrap(True)
        self.now_label.setFont(_sans(12))
        self.now_label.setStyleSheet(
            f"color: {INK}; background: #14110d; border-radius: 8px; padding: 8px;"
        )
        inner_lay.addWidget(self.now_label)

        inner_lay.addWidget(
            _help_block(
                "THIS PLATE TOGGLES ONE THING",
                "Unused GT 750M power, and only while Intel already owns the "
                "internal panel. Wi-Fi, brightness, apps, storage/AHCI, and "
                "the rest of the machine are unrelated — leave those alone "
                "from here.",
            )
        )
        inner_lay.addWidget(
            _help_block(
                "WORK DESK  ·  MONITORS",
                "Native HDMI and Thunderbolt outputs are on the 750M. At a "
                "desk (AC, or any extra screen already connected) the 750M "
                "stays awake — amber jewel is correct. Do not Sleep 750M "
                "to “save heat” while you need those ports. USB DisplayLink "
                "is a different, hotter path.",
                KEPLER,
            )
        )
        inner_lay.addWidget(
            _help_block(
                "NO COMMUTE PROFILE",
                "This machine is not used on the road, so it does not "
                "auto-sleep the 750M or drop to power-saver when you unplug. "
                "Brightness stays yours; Intel no longer forces gmux to max. "
                "Do not re-enable i915 display C-states.",
                COOL,
            )
        )
        inner_lay.addWidget(
            _help_block(
                "LID-ONLY AT HOME",
                "Browser and coding on the internal panel only: Sleep 750M "
                "if you want less heat (sage jewel). Iris Pro is already "
                "the display GPU.",
                COOL,
            )
        )
        inner_lay.addWidget(
            _help_block(
                "OPENGL ON THE 750M  ·  TOGGLE",
                "Type a command (or … browse) and hit Run on 750M. The plate "
                "wakes the chip if it is asleep, then starts the process with "
                "DRI_PRIME=1. Sleep 750M when that app exits. The lid stays "
                "on Intel — this is not macOS Automatic Graphics Switching.",
                KEPLER,
            )
        )
        inner_lay.addWidget(
            _help_block(
                "STEAM",
                "Put steam in the box and Run on 750M for native OpenGL titles. "
                "Most Windows/Proton games use Vulkan, which on this Intel-lid "
                "boot is Iris Pro — drop the in-game resolution; this panel is "
                "2880×1800. NVIDIA 470 Vulkan is a different Limine boot.",
                KEPLER,
            )
        )
        inner_lay.addWidget(
            _help_block(
                "CUDA / NVIDIA 470  ·  NOT THIS PLATE",
                "Reboot the NVIDIA LTS Limine recovery entry. Do not bind "
                "the 470 driver on this Intel-lid session, and do not look "
                "for a 470 toggle here.",
                FAULT,
            )
        )
        inner_lay.addWidget(
            _help_block(
                "JEWEL",
                "Sage = Intel lid, 750M asleep (idle default).\n"
                "Amber = Intel lid, 750M powered (prime-run can work).\n"
                "Red = not i915, or the helper failed.",
            )
        )
        inner_lay.addWidget(
            _help_block(
                "NEVER FROM THIS PLATE",
                "No IGD / DIS mux hops — those black the lid on this indexed "
                "Apple GMUX, and the helper refuses them. Escape or the jewel "
                "closes the plate; ? comes back here.",
                FAULT,
            )
        )
        inner_lay.addWidget(
            _help_block(
                "OMARCHY / MACOS",
                "Do not run the stock Omarchy ISO against this internal SSD — "
                "that path wipes the disk. Keep a macOS partition; it is the "
                "local recovery when Linux blacks the lid. Details: "
                "docs/graphics/max-value-and-omarchy.md in the RetinaForge repo.",
                MUTED,
            )
        )

        back = QPushButton("Back to plate")
        back.setCursor(Qt.CursorShape.PointingHandCursor)
        back.setFixedHeight(32)
        back.setFont(_sans(12, True))
        back.setStyleSheet(
            f"QPushButton {{ background: {IRIS}; color: #1a1611; border: 0;"
            " border-radius: 7px; }}"
        )
        back.clicked.connect(self.show_status)
        inner_lay.addWidget(back)
        inner_lay.addStretch(1)
        scroll.setWidget(inner)
        return scroll

    def help_visible(self) -> bool:
        return self.stack.currentIndex() == 1

    def show_status(self) -> None:
        self.stack.setCurrentIndex(0)
        self.help_btn.setText("?")
        self.help_btn.setToolTip("How this plate works")

    def show_help(self) -> None:
        self.stack.setCurrentIndex(1)
        self.help_btn.setText("×")
        self.help_btn.setToolTip("Back to plate")

    def toggle_help(self) -> None:
        if self.help_visible():
            self.show_status()
        else:
            self.show_help()

    def keyPressEvent(self, event) -> None:
        if event.key() == Qt.Key.Key_Escape:
            if self.help_visible():
                self.show_status()
                return
            self.hide()
            return
        super().keyPressEvent(event)

    def hideEvent(self, event) -> None:
        self.show_status()
        super().hideEvent(event)

    def apply(self, status: dict) -> None:
        if not status.get("ok"):
            self.title.setText("Helper failed")
            self._badge("ERR", FAULT)
            self.err.setText(status.get("error") or "unknown error")
            self.sleep_btn.setEnabled(False)
            self.wake_btn.setEnabled(False)
            if hasattr(self, "run_btn"):
                self.run_btn.setEnabled(False)
            if hasattr(self, "now_label"):
                self.now_label.setText(
                    "Right now: helper failed. Sleep/Wake are blocked until status works again."
                )
            return
        self.err.setText("" if status.get("product_ok", True) else f"DMI {status.get('product')} — writes blocked")
        intel = status.get("intel_lid")
        dis_on = status.get("dis_on")
        if intel and not dis_on:
            self.title.setText("Lid on Iris Pro")
            self._badge("COOL", IRIS)
            self.note.setText("750M is asleep. Run on 750M wakes it, then DRI_PRIME=1. Mux stays on Intel.")
            now = (
                "Right now: sage / COOL. That is the idle default. "
                "Use Run on 750M only when you are about to start an OpenGL app."
            )
        elif intel and dis_on:
            self.title.setText("Lid Intel · 750M awake")
            self._badge("AWAKE", KEPLER)
            self.note.setText("750M is powered. Run on 750M uses it. Sleep it when that app exits.")
            now = (
                "Right now: amber / AWAKE. Fine for prime-run. "
                "Sleep 750M when that app is done so the chassis can cool."
            )
        else:
            self.title.setText("Lid not on i915")
            self._badge("FAULT", FAULT)
            self.note.setText("This plate expects the Intel UKI path (i915drmfb). Mux hops are refused.")
            now = (
                "Right now: not on i915. Do not hunt for an IGD/DIS toggle here — "
                "this plate will not send mux hops. Boot the Intel UKI."
            )
        if hasattr(self, "now_label"):
            self.now_label.setText(now)
        edp = status.get("edp") or ""
        fb = status.get("fb") or ""
        self.subtitle.setText("  ·  ".join(part for part in (edp, fb) if part) or "no eDP / fb0")
        cpu = status.get("cpu_c")
        self.cpu.set_reading(
            cpu,
            f"{cpu:.0f}°" if cpu is not None else "—",
            COOL if (cpu or 0) < 75 else KEPLER,
        )
        gpu = status.get("dgpu_c")
        self.gpu.set_reading(
            gpu,
            f"{gpu:.0f}°" if gpu is not None else "—",
            KEPLER if dis_on else MUTED,
        )
        left, right = status.get("fan_l"), status.get("fan_r")
        fans = [v for v in (left, right) if isinstance(v, (int, float))]
        if fans:
            fan_label = "·".join(f"{int(v)}" for v in (left, right) if isinstance(v, (int, float)))
            self.fans.set_reading(max(fans), fan_label, IRIS if max(fans) < 3500 else KEPLER)
        else:
            self.fans.set_reading(None, "—", MUTED)
        igd = "IGD:+" if status.get("igd_sel") else "IGD"
        dis = "DIS:+" if status.get("dis_sel") else "DIS"
        self.mux.setText(f"{igd}:{status.get('igd')}   {dis}:{status.get('dis')}")
        self.sleep_btn.setEnabled(bool(dis_on) and status.get("product_ok", True))
        self.wake_btn.setEnabled((not dis_on) and status.get("product_ok", True))
        if hasattr(self, "run_btn"):
            self.run_btn.setEnabled(bool(intel) and status.get("product_ok", True))

    def _badge(self, text: str, color: str) -> None:
        self.badge.setText(text)
        self.badge.setStyleSheet(f"background: {color}; color: #1a1611; border-radius: 8px;")

    def show_near_cursor(self) -> None:
        pos = QCursor.pos()
        geo = self.geometry()
        geo.moveTopLeft(pos - QPoint(self.width() - 28, 16))
        app = QGuiApplication.instance()
        screen = app.screenAt(pos) if app is not None else None
        if screen is None:
            screen = QGuiApplication.primaryScreen()
        if screen:
            avail = screen.availableGeometry()
            geo.moveLeft(min(max(geo.left(), avail.left() + 8), avail.right() - geo.width() - 8))
            geo.moveTop(min(max(geo.top(), avail.top() + 8), avail.bottom() - geo.height() - 8))
        self.move(geo.topLeft())
        self.show()
        self.raise_()

    def browse_command(self) -> None:
        path, _filt = QFileDialog.getOpenFileName(
            self,
            "Run on 750M",
            str(Path.home()),
            "Programs (*.desktop *);;All files (*)",
        )
        if not path:
            return
        picked = Path(path)
        if picked.suffix == ".desktop":
            exec_line = desktop_exec_line(picked)
            if not exec_line:
                self.err.setText("no Exec= in that .desktop")
                return
            self.cmd_edit.setText(exec_line)
            return
        self.cmd_edit.setText(path)

    def remember_command(self, raw: str) -> None:
        items = [raw] + [item for item in self._prime_history if item != raw]
        self._prime_history = items[:12]
        save_prime_history(self._prime_history)
        self._completer = QCompleter(self._prime_history)
        self._completer.setCaseSensitivity(Qt.CaseSensitivity.CaseInsensitive)
        self.cmd_edit.setCompleter(self._completer)

    def focus_run(self) -> None:
        self.show_status()
        self.cmd_edit.setFocus()
        self.cmd_edit.selectAll()


class Controller:
    def __init__(self) -> None:
        self.busy = False
        self.status: dict = {}
        self.plate = Plate(self)
        self.tray = QSystemTrayIcon()
        self.tray.setToolTip("RetinaForge 11,3")
        self.tray.activated.connect(self._click)
        menu = QMenu()
        open_act = QAction("Open plate", self.tray)
        open_act.triggered.connect(self.toggle)
        sleep_act = QAction("Sleep 750M", self.tray)
        sleep_act.triggered.connect(lambda: self.act("dis-off"))
        wake_act = QAction("Wake 750M", self.tray)
        wake_act.triggered.connect(lambda: self.act("dis-on"))
        quit_act = QAction("Quit", self.tray)
        quit_act.triggered.connect(QApplication.quit)
        menu.addAction(open_act)
        menu.addAction(sleep_act)
        menu.addAction(wake_act)
        run_act = QAction("Run on 750M…", self.tray)
        run_act.triggered.connect(self.open_run)
        menu.addAction(run_act)
        help_act = QAction("What is this?", self.tray)
        help_act.triggered.connect(self.open_help)
        menu.addAction(help_act)
        menu.addSeparator()
        menu.addAction(quit_act)
        self.tray.setContextMenu(menu)
        self.refresh()
        self.timer = QTimer()
        self.timer.timeout.connect(self.refresh)
        self.timer.start(8000)
        self.tray.setVisible(True)

    def _click(self, reason) -> None:
        if reason in (
            QSystemTrayIcon.ActivationReason.Trigger,
            QSystemTrayIcon.ActivationReason.DoubleClick,
        ):
            self.toggle()

    def toggle(self) -> None:
        try:
            if self.plate.isVisible():
                self.plate.hide()
                return
            self.refresh()
            self.plate.show_near_cursor()
        except Exception:
            traceback.print_exc()

    def open_help(self) -> None:
        try:
            self.refresh()
            self.plate.show_help()
            if not self.plate.isVisible():
                self.plate.show_near_cursor()
        except Exception:
            traceback.print_exc()

    def open_run(self) -> None:
        try:
            self.refresh()
            if not self.plate.isVisible():
                self.plate.show_near_cursor()
            self.plate.focus_run()
        except Exception:
            traceback.print_exc()

    def launch_on_750m(self) -> None:
        if self.busy:
            return
        raw = self.plate.cmd_edit.text().strip()
        if not raw:
            self.plate.err.setText("Type a command or browse to a binary.")
            return
        try:
            argv = shlex.split(raw)
        except ValueError as exc:
            self.plate.err.setText(str(exc))
            return
        if not argv:
            self.plate.err.setText("empty command")
            return
        program = argv[0]
        if program.endswith(".desktop"):
            parsed = desktop_exec_line(Path(program))
            if not parsed:
                self.plate.err.setText("no Exec= in that .desktop")
                return
            try:
                argv = shlex.split(parsed)
            except ValueError as exc:
                self.plate.err.setText(str(exc))
                return
            program = argv[0]
        if not os.path.isabs(program):
            found = shutil.which(program)
            if not found:
                self.plate.err.setText(f"not on PATH: {program}")
                return
            argv[0] = found
        elif not os.path.isfile(argv[0]) or not os.access(argv[0], os.X_OK):
            self.plate.err.setText(f"not executable: {argv[0]}")
            return
        if not self.status.get("ok") or not self.status.get("intel_lid"):
            self.plate.err.setText("Need the Intel lid (i915drmfb) first.")
            return
        if not self.status.get("product_ok", True):
            self.plate.err.setText("writes blocked on this DMI")
            return
        if not self.status.get("dis_on"):
            self.act("dis-on")
            if not self.status.get("dis_on"):
                self.plate.err.setText("could not wake the 750M")
                return
        env = QProcessEnvironment.systemEnvironment()
        env.insert("DRI_PRIME", "1")
        wrapper = shutil.which("prime-run")
        if wrapper:
            program, args = wrapper, argv
        else:
            program, args = argv[0], argv[1:]
        proc = QProcess()
        proc.setProgram(program)
        proc.setArguments(args)
        proc.setProcessEnvironment(env)
        proc.setWorkingDirectory(str(Path.home()))
        result = proc.startDetached()
        pid = None
        if isinstance(result, tuple):
            ok = bool(result[0])
            if len(result) > 1:
                pid = result[1]
        else:
            ok = bool(result)
        if not ok:
            self.plate.err.setText("launch failed")
            return
        self.plate.remember_command(raw)
        extra = f" pid {pid}" if pid else ""
        self.plate.err.setText("")
        self.plate.note.setText(f"Started on 750M{extra}. Sleep 750M when that app exits.")

    def refresh(self) -> None:
        if self.busy:
            return
        try:
            self.apply(run_helper("status"))
        except Exception:
            traceback.print_exc()

    def act(self, cmd: str) -> None:
        if self.busy:
            return
        self.busy = True
        self.plate.sleep_btn.setEnabled(False)
        self.plate.wake_btn.setEnabled(False)
        self.plate.run_btn.setEnabled(False)
        QApplication.setOverrideCursor(Qt.CursorShape.WaitCursor)
        QApplication.processEvents()
        try:
            self.apply(run_helper(cmd))
        finally:
            QApplication.restoreOverrideCursor()
            self.busy = False

    def apply(self, status: dict) -> None:
        self.status = status
        self.plate.apply(status)
        self.tray.setIcon(make_tray_icon(lamp_color(status)))
        if status.get("ok"):
            cpu = status.get("cpu_c")
            dis = status.get("dis")
            tip = "RetinaForge 11,3"
            if cpu is not None:
                tip += f"\nCPU {cpu:.0f}°  DIS {dis}"
            self.tray.setToolTip(tip)
        else:
            self.tray.setToolTip("RetinaForge 11,3 — helper error")


def main() -> int:
    faulthandler.enable()
    os.environ.setdefault("QT_QPA_PLATFORM", "xcb")
    os.environ.setdefault("QT_XCB_GL_INTEGRATION", "none")
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    app.setApplicationName("RetinaForge plate")
    app.setOrganizationName("RetinaForge")
    if not QSystemTrayIcon.isSystemTrayAvailable():
        print("no system tray", file=sys.stderr)
        return 1
    controller = Controller()
    if "--open" in sys.argv:
        QTimer.singleShot(200, controller.toggle)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
