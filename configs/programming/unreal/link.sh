#!/usr/bin/env bash

# a ~60 GB engine is a desktop workload; unwanted counts as done, so a hook an older config armed retires
unreal_done() {
    [[ "$FORM_FACTOR" != desktop ]] || pacman -Q unreal-engine-bin >/dev/null 2>&1
}
user_hook_oneshot ./hook unreal-install unreal_done

# bridge and fab plugins go into /opt through sudo, so they are a command the install hook also runs, never config
[[ "$FORM_FACTOR" != desktop ]] || link_commands unreal-install-plugins.sh
