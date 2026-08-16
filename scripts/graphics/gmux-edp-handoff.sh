#!/usr/bin/env bash
# gmux-edp-handoff.sh — indexed GMUX eDP link training on DIS, then switch to IGD.

set -euo pipefail

log() { logger -t retinaforge-edp-handoff "$*"; printf '%s\n' "$*"; }

# Never block display-manager for long — poll briefly, log, exit 0 either way.
wait_max="${GMUX_HANDOFF_WAIT_SEC:-3}"

mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true
switch_path=/sys/kernel/debug/vgaswitcheroo/switch

modprobe nouveau 2>/dev/null || true

dis_edp=""
for i in $(seq 1 "$wait_max"); do
	for s in /sys/class/drm/card0-eDP-*/status; do
		[[ -e "$s" ]] || continue
		if [[ "$(cat "$s")" == connected ]]; then
			dis_edp=$(basename "$(dirname "$s")")
			break 2
		fi
	done
	sleep 1
done

if [[ -z "$dis_edp" ]]; then
	log "WARN: no connected card0 eDP after ${wait_max}s — continuing anyway"
else
	log "DIS eDP ready: ${dis_edp}"
	if command -v modetest >/dev/null 2>&1; then
		modes=$(modetest -M nouveau -c 2>/dev/null | grep -c 'mode' || true)
		log "nouveau connector modes (modetest -c lines): ${modes}"
	fi
fi

# i915 must load before vga_switcheroo sysfs appears (needs both GPU clients).
# UKI cmdline blacklists early autoload; -f loads it here after nouveau trains.
modprobe -f i915 2>/dev/null || modprobe -f i915

for i in $(seq 1 15); do
	[[ -e "$switch_path" ]] && break
	sleep 1
done

if [[ ! -e "$switch_path" ]]; then
	log "ERROR: vgaswitcheroo missing after i915 load — cannot hand off panel"
	exit 1
fi

log "switcheroo before IGD:"
log "$(tr '\n' ' | ' <"$switch_path")"

if ! echo IGD >"$switch_path" 2>/dev/null; then
	log "ERROR: echo IGD failed"
	exit 1
fi

sleep 1

log "switcheroo after IGD:"
log "$(tr '\n' ' | ' <"$switch_path")"

sleep 2

intel_edp=""
intel_modes=0
for i in $(seq 1 "$wait_max"); do
	for card in /sys/class/drm/card*; do
		[[ -d "$card/device/driver" ]] || continue
		driver=$(readlink -f "$card/device/driver" | xargs basename)
		[[ "$driver" == i915 ]] || continue
		for s in "$card"-eDP-*/status; do
			[[ -e "$s" ]] || continue
			if [[ "$(cat "$s")" == connected ]]; then
				intel_edp=$(basename "$(dirname "$s")")
				if command -v modetest >/dev/null 2>&1; then
					conn_id=$(modetest -M i915 -c 2>/dev/null | awk -v n="$intel_edp" '$0 ~ n {print $1; exit}')
					if [[ -n "$conn_id" ]]; then
						intel_modes=$(modetest -M i915 -c 2>/dev/null | awk -v id="$conn_id" '$1==id {f=1} f && /mode/ {c++} END{print c+0}')
					fi
				fi
				log "i915 ${intel_edp} connected; kernel modes=${intel_modes}"
				if [[ "$intel_modes" -gt 0 ]]; then
					break 3
				fi
			fi
		done
	done
	sleep 1
done

if [[ "$intel_modes" -eq 0 ]]; then
	log "WARN: i915 eDP still has 0 kernel DRM modes after IGD handoff"
fi

if grep -qE 'DIS:.*Pwr' "$switch_path" 2>/dev/null; then
	echo OFF >"$switch_path" 2>/dev/null || true
	log "powered down DIS client"
fi

log "handoff complete (intel_edp=${intel_edp:-none} modes=${intel_modes})"
exit 0
