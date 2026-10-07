#!/usr/bin/env bash

# a ~60 GB engine is a desktop workload; elsewhere a hook an older config armed just retires
if [[ "$FORM_FACTOR" != desktop ]]; then
    user_hook_retire unreal-install
    exit 0
fi

# the old pacman install in /opt stays until removed by hand: dropping it here could leave no engine when the zip is
# gone from ~/sync, and a second ~60 GB copy is no better
if pacman -Q unreal-engine-bin >/dev/null 2>&1; then
    user_hook_retire unreal-install
    echo "unreal: the old /opt engine is still installed; removing the unreal-engine-bin package (pacman -R, as root) moves it into the home on the next config" >&2
    exit 0
fi

unreal_installed() { [[ -f "${XDG_DATA_HOME:-${HOME}/.local/share}/unreal-engine/.installed-from" ]]; }
# the newest zip installs here, first install or a later version, into the home: no root, never asked
./hook/unreal-install.sh
# still missing (no zip yet): the path unit waits for one
user_hook_oneshot ./hook unreal-install unreal_installed
# bridge and fab again after a new plugin zip, without a new engine
link_commands unreal-install-plugins.sh
