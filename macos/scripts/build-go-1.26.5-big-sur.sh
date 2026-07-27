#!/bin/bash
# Build Go 1.26.5 alongside the installed toolchain on Intel macOS Big Sur.

set -euo pipefail

go_version="1.26.5"
source_sha256="495be4bc87176ac567392e5b4116abd98466d33d7b49d41e764ccc6976b2dc42"
source_archive="go${go_version}.src.tar.gz"
source_url="https://go.dev/dl/${source_archive}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
patch_file="$repo_root/patches/go-1.26.5-big-sur.patch"

if [ "$(uname -s)" != "Darwin" ]; then
    printf 'error: this compatibility build targets macOS\n' >&2
    exit 1
fi

if [ "$(uname -m)" != "x86_64" ]; then
    printf 'error: this build has only been validated on Intel x86_64\n' >&2
    exit 1
fi

for command_name in curl shasum tar patch go; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'error: required command not found: %s\n' "$command_name" >&2
        exit 1
    fi
done

if [ ! -r "$patch_file" ]; then
    printf 'error: patch not found: %s\n' "$patch_file" >&2
    exit 1
fi

bootstrap_root=$(go env GOROOT)
build_root=$(mktemp -d "${TMPDIR:-/tmp}/go-1.26.5-big-sur.XXXXXX")
archive_path="$build_root/$source_archive"

printf 'Build workspace: %s\n' "$build_root"
printf 'Bootstrap GOROOT: %s\n' "$bootstrap_root"
printf 'Downloading authenticated Go source...\n'

curl --fail --location --proto '=https' --tlsv1.2 \
    --output "$archive_path" "$source_url"

printf '%s  %s\n' "$source_sha256" "$archive_path" | shasum -a 256 -c -
tar -xzf "$archive_path" -C "$build_root"
patch -d "$build_root/go" -p0 < "$patch_file"

printf 'Building Go %s...\n' "$go_version"
(
    cd "$build_root/go/src"
    GOROOT_BOOTSTRAP="$bootstrap_root" ./make.bash
)

new_go="$build_root/go/bin/go"
"$new_go" version

printf 'Running targeted compatibility tests...\n'
"$new_go" test crypto/x509 crypto/tls net/http runtime

printf '\nBuild and targeted tests completed.\n'
printf 'Patched GOROOT: %s\n' "$build_root/go"
printf 'The workspace was left in place for inspection.\n'
