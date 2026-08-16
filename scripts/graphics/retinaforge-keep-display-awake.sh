#!/bin/sh
# Keep the active X11 display awake without depending on SDDM's private auth file.

set -u

display=${DISPLAY:-:0}

find_xauthority() {
	if [ -n "${XAUTHORITY:-}" ] && [ -r "$XAUTHORITY" ]; then
		printf '%s\n' "$XAUTHORITY"
		return 0
	fi

	for candidate in /tmp/xauth_*; do
		if [ -r "$candidate" ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	return 1
}

run_xset() {
	auth=$1
	shift
	DISPLAY="$display" XAUTHORITY="$auth" /usr/bin/xset "$@" >/dev/null 2>&1 || true
}

first=1
while :; do
	auth=$(find_xauthority 2>/dev/null || true)
	if [ -n "$auth" ]; then
		run_xset "$auth" s off
		run_xset "$auth" s noblank
		run_xset "$auth" -dpms
		if [ "$first" -eq 1 ]; then
			run_xset "$auth" dpms force on
			first=0
		fi
	fi
	sleep 15
done
