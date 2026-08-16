#!/usr/bin/env bash
# Install the MacBookPro11,3 RetinaForge tray plate (helper, polkit, autostart).
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
prefix="${PREFIX:-/usr/local}"
helper_dst="${prefix}/libexec/retinaforge-mbp-helper"
panel_share="${prefix}/share/retinaforge/mbp-panel"
panel_bin="${prefix}/bin/retinaforge-mbp-panel"

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

product="$(tr -d '\n' </sys/class/dmi/id/product_name 2>/dev/null || true)"
if [[ ${product} != MacBookPro11,3 ]]; then
	echo "warning: this plate is written for MacBookPro11,3 (found: ${product:-unknown})" >&2
fi

if ! python3 -c "import PyQt6" 2>/dev/null && ! python3 -c "import PySide6" 2>/dev/null; then
	if command -v pacman >/dev/null 2>&1; then
		echo "install python-pyqt6 (and optionally ttf-ibm-plex) then re-run" >&2
		echo "  pacman -S --needed python-pyqt6 ttf-ibm-plex polkit" >&2
	else
		echo "need a Qt6 Python binding: python-pyqt6 or python-pyside6" >&2
	fi
	exit 1
fi

install -d "${prefix}/libexec" "${prefix}/bin" "${panel_share}" \
	/usr/share/polkit-1/actions /etc/polkit-1/rules.d \
	/usr/share/applications /etc/xdg/autostart \
	/usr/share/icons/hicolor/scalable/apps

install -Dm755 "${root}/retinaforge-mbp-helper.py" "${helper_dst}"
# pkexec refuses world-writable helpers.
chown root:root "${helper_dst}"
chmod 0755 "${helper_dst}"

install -Dm644 "${root}/retinaforge-mbp-panel.py" "${panel_share}/retinaforge-mbp-panel.py"
install -Dm755 "${root}/start-on-seat.sh" "${prefix}/sbin/retinaforge-mbp-panel-start-on-seat"
cat >"${panel_bin}" <<EOF
#!/bin/sh
export QT_QPA_PLATFORM=xcb
export QT_XCB_GL_INTEGRATION=none
exec python3 ${panel_share}/retinaforge-mbp-panel.py "\$@"
EOF
chmod 0755 "${panel_bin}"

install -Dm644 "${root}/org.retinaforge.mbp.policy" \
	/usr/share/polkit-1/actions/org.retinaforge.mbp.policy
install -Dm644 "${root}/org.retinaforge.mbp.rules" \
	/etc/polkit-1/rules.d/50-org.retinaforge.mbp.rules
install -Dm644 "${root}/retinaforge-mbp-panel.svg" \
	/usr/share/icons/hicolor/scalable/apps/retinaforge-mbp-panel.svg
install -Dm644 "${root}/retinaforge-mbp-panel.desktop" \
	/usr/share/applications/retinaforge-mbp-panel.desktop
install -Dm644 "${root}/retinaforge-mbp-panel.desktop" \
	/etc/xdg/autostart/retinaforge-mbp-panel.desktop

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
	gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
	update-desktop-database -q /usr/share/applications 2>/dev/null || true
fi

echo "installed ${panel_bin}"
echo "tray autostart: /etc/xdg/autostart/retinaforge-mbp-panel.desktop"
echo "helper: ${helper_dst} (status | dis-off | dis-on; mux hops refused)"
echo "from SSH: sudo ${prefix}/sbin/retinaforge-mbp-panel-start-on-seat"
