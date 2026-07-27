#!/bin/bash
# Install a conservative native development baseline on Intel macOS Big Sur.
# Run as root after installing MacPorts from the official Big Sur package.

set -euo pipefail

export PATH="/opt/local/bin:/opt/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

if [ "$(id -u)" -ne 0 ]; then
    printf 'error: this script must run as root\n' >&2
    exit 1
fi

if [ ! -x /opt/local/bin/port ]; then
    printf 'error: MacPorts is not installed at /opt/local\n' >&2
    exit 1
fi

printf 'Updating the MacPorts catalog...\n'
port -N selfupdate

printf 'Installing Git with the macOS Keychain credential helper...\n'
port -N install git +credential_osxkeychain

printf 'Installing Node.js, npm, Python, and pip...\n'
port -N install nodejs22 npm10 python313 py313-pip

printf 'Selecting the MacPorts Python toolchain...\n'
port -N select --set python python313
port -N select --set python3 python313
port -N select --set pip pip313
port -N select --set pip3 pip313

printf 'Installing Rust, Cargo, Go, and native build tools...\n'
port -N install rust cargo go cmake ninja pkgconfig

printf 'Installing terminal development utilities...\n'
port -N install neovim ripgrep fd jq tmux gh tree

printf 'Native development baseline installation completed.\n'
