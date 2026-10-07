#!/usr/bin/env bash

# the owner's jai beta, synced into ~/sync
profile_has identity || exit 0

jai_installed() { [[ -x "${HOME}/.jai/bin/jai-linux" ]]; }
user_hook_oneshot ./hook jai-install jai_installed
# installed: a newer beta zip in ~/sync installs here, no watcher left to catch it
if jai_installed; then
    ./hook/jai-install.sh
fi
