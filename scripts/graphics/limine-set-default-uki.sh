#!/usr/bin/env bash
# limine-set-default-uki.sh — UKI as a flat top-level entry with autoboot countdown.
#
# Limine v12: default_entry is 1-based. Directories (entries with sub-entries)
# cannot autoboot — do not wrap the UKI in /+Folder with //child underneath.

set -euo pipefail

limine_conf=/boot/limine.conf
timeout="${LIMINE_TIMEOUT:-5}"
uki_path='boot():/EFI/Linux/cachyos-apple-set-os.efi'
uki_title='RetinaForge Intel UKI'

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

[[ -f "$limine_conf" ]] || {
	echo "missing ${limine_conf}" >&2
	exit 1
}

cp -a "$limine_conf" "${limine_conf}.bak-before-uki-autoboot-$(date +%Y%m%d-%H%M%S)"

python3 - "$limine_conf" "$timeout" "$uki_title" "$uki_path" <<'PY'
import pathlib
import re
import sys

path, timeout, title, uki_path = sys.argv[1:5]
text = pathlib.Path(path).read_text()

# Strip old Intel-probe submenu blocks (flat or nested).
text = re.sub(r"/\+CachyOS Intel probe.*?(?=\n/|\ncomment: machine-id|\Z)", "", text, flags=re.S)
text = re.sub(r"/RetinaForge Intel UKI.*?(?=\n/|\ncomment: machine-id|\Z)", "", text, flags=re.S)

uki_block = f"""/{title}
comment: UKI via EFI stub for apple_set_os (autoboot default)
protocol: efi
path: {uki_path}

"""

parts = re.split(r"(comment: machine-id=)", text, maxsplit=1)
if len(parts) == 3:
    prefix, marker, rest = parts[0], parts[1], parts[2]
else:
    prefix, marker, rest = text, "", ""

prefix = re.sub(r"^timeout:.*$", f"timeout: {timeout}", prefix, flags=re.M)
prefix = re.sub(r"^default_entry:.*$", "default_entry: 1", prefix, flags=re.M)
prefix = re.sub(r"^remember_last_entry:.*$", "remember_last_entry: no", prefix, flags=re.M)
if "default_entry:" not in prefix:
    prefix = prefix.rstrip() + "\ndefault_entry: 1\n"
if "remember_last_entry:" not in prefix:
    prefix = prefix.rstrip() + "\nremember_last_entry: no\n"

new_text = prefix.rstrip() + "\n\n" + uki_block + marker + rest
pathlib.Path(path).write_text(new_text)
print(f"wrote {path}: flat UKI entry 1, timeout={timeout}s, default_entry=1")
PY

echo "UKI autoboot: ${timeout}s countdown, entry 1 = ${uki_title}"
echo "Emergency discrete boot: pick linux-cachyos-lts in the CachyOS submenu."
