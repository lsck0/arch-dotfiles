#!/usr/bin/env bash

# the owner's jai beta, synced into ~/sync
profile_has identity || exit 0

jai_installed() { [[ -x "${HOME}/.jai/bin/jai-linux" ]]; }
# the newest zip installs here, first install or a later beta
./hook/jai-install.sh
# still missing (no zip yet): the path unit waits for one
user_hook_oneshot ./hook jai-install jai_installed
