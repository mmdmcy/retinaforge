#!/usr/bin/env bash
# diff-intel-uki-contents.sh — read-only compare of current vs historical Intel UKIs.
# Run on the Linux lab OS. Does not change Limine default or rebuild anything.

set -euo pipefail

UKI_DIR="${UKI_DIR:-/boot/EFI/Linux}"
CUR="${CUR_UKI:-${UKI_DIR}/cachyos-apple-set-os.efi}"
HIST="${HIST_UKI:-${UKI_DIR}/cachyos-intel-historical-baseline.efi}"
WORKDIR="${WORKDIR:-/tmp/retinaforge-uki-diff}"

if ((EUID != 0)); then
	echo "run as root: sudo $0" >&2
	exit 1
fi

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/cur" "$WORKDIR/hist"
cp -a "$CUR" "$WORKDIR/current.efi"
cp -a "$HIST" "$WORKDIR/historical.efi"

echo "=== sizes/hashes ==="
stat -c '%n %s' "$WORKDIR/current.efi" "$WORKDIR/historical.efi"
sha256sum "$WORKDIR/current.efi" "$WORKDIR/historical.efi"

echo "=== PE sections current ==="
objdump -h "$WORKDIR/current.efi" | awk '/\.linux|\.initrd|\.cmdline|\.osrel|\.uname|\.sbat|\.splash/'
echo "=== PE sections historical ==="
objdump -h "$WORKDIR/historical.efi" | awk '/\.linux|\.initrd|\.cmdline|\.osrel|\.uname|\.sbat|\.splash/'

extract_meta() {
	local src="$1" dest="$2"
	objcopy \
		--dump-section .cmdline="$dest/cmdline" \
		--dump-section .osrel="$dest/osrel" \
		--dump-section .uname="$dest/uname" \
		--dump-section .initrd="$dest/initrd.img" \
		"$src" "$dest/stripped.efi"
	rm -f "$dest/stripped.efi"
}

extract_meta "$WORKDIR/current.efi" "$WORKDIR/cur"
extract_meta "$WORKDIR/historical.efi" "$WORKDIR/hist"

echo "=== cmdline current ==="
tr -d '\0' <"$WORKDIR/cur/cmdline"
echo
echo "=== cmdline historical ==="
tr -d '\0' <"$WORKDIR/hist/cmdline"
echo
echo "=== uname current ==="
tr -d '\0' <"$WORKDIR/cur/uname" 2>/dev/null || true
echo
echo "=== uname historical ==="
tr -d '\0' <"$WORKDIR/hist/uname" 2>/dev/null || true
echo
echo "=== initrd sizes ==="
stat -c '%n %s' "$WORKDIR/cur/initrd.img" "$WORKDIR/hist/initrd.img"

list_initrd() {
	local img="$1" out="$2"
	if command -v lsinitcpio >/dev/null 2>&1; then
		lsinitcpio -A "$img" >"$out" || lsinitcpio "$img" >"$out"
	else
		mkdir -p "${out}.dir"
		(cd "${out}.dir" && bsdtar -tf "$img") >"$out"
	fi
}

list_initrd "$WORKDIR/cur/initrd.img" "$WORKDIR/cur/initrd.list"
list_initrd "$WORKDIR/hist/initrd.img" "$WORKDIR/hist/initrd.list"

echo "=== initrd file counts ==="
wc -l "$WORKDIR/cur/initrd.list" "$WORKDIR/hist/initrd.list"

summarize() {
	local list="$1"
	echo "-- firmware --"
	grep -E 'usr/lib/firmware/' "$list" | sed 's|.*/firmware/||' | sort -u | head -200
	echo "-- modules (basename) --"
	grep -E '\.ko(\.zst|\.xz)?$' "$list" | sed 's|.*/||; s/\.ko.*//' | sort -u
}

echo "=== current firmware/modules ==="
summarize "$WORKDIR/cur/initrd.list"
echo "=== historical firmware/modules ==="
summarize "$WORKDIR/hist/initrd.list"

echo "=== firmware only-in-historical ==="
comm -13 \
	<(grep -E 'usr/lib/firmware/' "$WORKDIR/cur/initrd.list" | sed 's|.*/firmware/||' | sort -u) \
	<(grep -E 'usr/lib/firmware/' "$WORKDIR/hist/initrd.list" | sed 's|.*/firmware/||' | sort -u) || true
echo "=== firmware only-in-current ==="
comm -23 \
	<(grep -E 'usr/lib/firmware/' "$WORKDIR/cur/initrd.list" | sed 's|.*/firmware/||' | sort -u) \
	<(grep -E 'usr/lib/firmware/' "$WORKDIR/hist/initrd.list" | sed 's|.*/firmware/||' | sort -u) || true
echo "=== modules only-in-historical ==="
comm -13 \
	<(grep -E '\.ko(\.zst|\.xz)?$' "$WORKDIR/cur/initrd.list" | sed 's|.*/||; s/\.ko.*//' | sort -u) \
	<(grep -E '\.ko(\.zst|\.xz)?$' "$WORKDIR/hist/initrd.list" | sed 's|.*/||; s/\.ko.*//' | sort -u) || true
echo "=== modules only-in-current ==="
comm -23 \
	<(grep -E '\.ko(\.zst|\.xz)?$' "$WORKDIR/cur/initrd.list" | sed 's|.*/||; s/\.ko.*//' | sort -u) \
	<(grep -E '\.ko(\.zst|\.xz)?$' "$WORKDIR/hist/initrd.list" | sed 's|.*/||; s/\.ko.*//' | sort -u) || true
