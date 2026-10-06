#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source $DOTFILES/scripts/lib/personal.sh
is_personal || exit 0

set -e

jai_installed() { [[ -x "${HOME}/.jai/bin/jai-linux" ]]; }
source $DOTFILES/scripts/lib/user-hook.sh
user_hook_oneshot ./hook jai-install jai_installed
# installed: a newer beta zip in ~/sync installs here, no watcher left to catch it
if jai_installed; then
    ./hook/jai-install.sh
fi
