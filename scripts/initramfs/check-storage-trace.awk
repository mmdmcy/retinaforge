#!/bin/awk -f
# SPDX-License-Identifier: GPL-2.0-only

function event_value(prefix, field_number, pair) {
	for (field_number = 1; field_number <= NF; field_number++) {
		if (substr($field_number, 1, length(prefix)) == prefix) {
			split($field_number, pair, "=")
			return pair[2]
		}
	}
	return ""
}

/ata_qc_issue:/ {
	port = event_value("ata_port=")
	device = event_value("ata_dev=")
	tag = event_value("tag=")
	command = event_value("cmd=")
	if (port == "" || device == "" || tag == "" || command == "") {
		parse_errors++
		next
	}
	key = port ":" device ":" tag
	if (key in outstanding) {
		duplicate_issues++
		next
	}
	outstanding[key] = command
	if (command == "ATA_CMD_FLUSH" || command == "ATA_CMD_FLUSH_EXT") {
		flush_issued++
		if (command == "ATA_CMD_FLUSH_EXT")
			flush_ext_issued++
	}
	next
}

/ata_qc_complete_done:|ata_qc_complete_failed:/ {
	port = event_value("ata_port=")
	device = event_value("ata_dev=")
	tag = event_value("tag=")
	if (port == "" || device == "" || tag == "") {
		parse_errors++
		next
	}
	key = port ":" device ":" tag
	if (!(key in outstanding)) {
		unmatched_completions++
		next
	}
	command = outstanding[key]
	delete outstanding[key]
	if ($0 ~ /ata_qc_complete_failed:/) {
		failed_commands++
		if (command == "ATA_CMD_FLUSH" || command == "ATA_CMD_FLUSH_EXT")
			failed_flushes++
		next
	}
	if (command == "ATA_CMD_FLUSH" || command == "ATA_CMD_FLUSH_EXT")
		flush_completed++
}

END {
	for (key in outstanding)
		unmatched_issues++
	if (flush_ext_issued < 1 || flush_completed != flush_issued ||
	    failed_flushes != 0 || failed_commands != 0 ||
	    unmatched_issues != 0 || unmatched_completions != 0 ||
	    duplicate_issues != 0 || parse_errors != 0)
		exit 1
}
