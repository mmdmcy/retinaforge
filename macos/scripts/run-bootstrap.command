#!/bin/bash
# Interactive launcher for bootstrap-big-sur-dev.sh.

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

printf 'MacBook native development setup\n'
printf 'macOS will ask for the administrator password below.\n\n'

sudo /bin/bash "$script_dir/bootstrap-big-sur-dev.sh"
status=$?

if [ "$status" -eq 0 ]; then
    printf '\nSetup completed successfully.\n'
else
    printf '\nSetup stopped with status %s. Codex will inspect the log.\n' "$status"
fi

printf 'You may close this window.\n'
exit "$status"
