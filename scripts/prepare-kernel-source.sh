#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Fetch and verify the exact upstream stable source used by the baseline.
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
source_dir=${KERNEL_SOURCE:-$repo_root/build/linux-v7.1.3}
gnupg_home=${KERNEL_GNUPGHOME:-$repo_root/build/gnupg-kernel}
remote=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
tag=v7.1.3
expected_commit=199c9959d3a9b53f346c221757fc7ac507fbac50
expected_fingerprint=647F28654894E3BD457199BE38DBBDC86092693E

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

for command in git gpg install realpath grep; do
	command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

build_root=$(realpath -m "$repo_root/build")
source_dir=$(realpath -m "$source_dir")
gnupg_home=$(realpath -m "$gnupg_home")
case "$source_dir/" in
	"$build_root"/*/) ;;
	*) die "KERNEL_SOURCE must remain below $build_root" ;;
esac
case "$gnupg_home/" in
	"$build_root"/*/) ;;
	*) die "KERNEL_GNUPGHOME must remain below $build_root" ;;
esac

if [[ ! -d $source_dir/.git ]]; then
	[[ ! -e $source_dir ]] || die "non-Git path already exists: $source_dir"
	install -d -m 0755 "$(dirname "$source_dir")"
	git init "$source_dir"
	git -C "$source_dir" remote add origin "$remote"
elif [[ $(git -C "$source_dir" remote get-url origin) != "$remote" ]]; then
	die "unexpected kernel origin: $(git -C "$source_dir" remote get-url origin)"
fi

if ! git -C "$source_dir" rev-parse --verify --quiet "refs/tags/$tag^{commit}" >/dev/null; then
	git -C "$source_dir" fetch --depth=1 origin tag "$tag"
fi

actual_commit=$(git -C "$source_dir" rev-parse "refs/tags/$tag^{commit}")
[[ $actual_commit == "$expected_commit" ]] || \
	die "$tag resolves to unexpected commit $actual_commit"

install -d -m 0700 "$gnupg_home"
if ! gpg --homedir "$gnupg_home" --batch --with-colons \
	--list-keys "$expected_fingerprint" 2>/dev/null | \
	grep "^fpr:::::::::$expected_fingerprint:" >/dev/null; then
	gpg --homedir "$gnupg_home" --batch \
		--auto-key-locate clear,wkd --locate-keys gregkh@kernel.org
fi

verification=$(GNUPGHOME="$gnupg_home" \
	git -C "$source_dir" verify-tag --raw "$tag" 2>&1) || {
	printf '%s\n' "$verification" >&2
	die "tag signature verification failed"
}
printf '%s\n' "$verification" | \
	grep "\[GNUPG:\] VALIDSIG $expected_fingerprint " >/dev/null || \
	die "tag was not signed by expected fingerprint $expected_fingerprint"

if [[ -n $(git -C "$source_dir" status --porcelain) ]]; then
	die "kernel source has local changes; refusing to change its checkout"
fi
if [[ $(git -C "$source_dir" rev-parse --verify HEAD 2>/dev/null || true) != "$expected_commit" ]]; then
	git -C "$source_dir" switch --detach "$tag"
fi

printf 'Verified %s at %s\n' "$tag" "$expected_commit"
printf 'Signer fingerprint: %s\n' "$expected_fingerprint"
printf 'Kernel source: %s\n' "$source_dir"
