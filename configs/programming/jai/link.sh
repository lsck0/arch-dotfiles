#!/usr/bin/env bash

# the owner's jai beta, synced into ~/sync/vendor
profile_has identity || exit 0

jai_installed() { [[ -x "${HOME}/.jai/bin/jai-linux" ]]; }
# the newest zip installs here, first install or a later beta
./hook/jai-install.sh
# still missing (no zip yet): the path unit waits for one. syncthing writes ~/sync in bursts, so keep the brake. no
# --mkdir: ~/sync is syncthing's, a dir made there before it delivers its own can collide; the unit watches the nearest
# existing parent until vendor/ appears
user_hook_oneshot jai-install jai_installed --watch "%h/sync/vendor"
