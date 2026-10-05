#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../scripts/lib/personal.sh
source ../../scripts/lib/platform.sh
source ../../scripts/lib/user-hook.sh

form_factor=$(platform_form_factor ../..) || exit 1

set -e

# a ~60 GB engine is a personal desktop workload; unwanted counts as done, so a hook an older config armed retires
unreal_done() {
    ! is_personal || [[ "$form_factor" != desktop ]] || pacman -Q unreal-engine-bin >/dev/null 2>&1
}
user_hook_oneshot ./hook unreal-install unreal_done
