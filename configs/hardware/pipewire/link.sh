#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source $DOTFILES/scripts/lib/platform.sh
# pipewire also arrives under wsl, as a dependency of the portals, where wslg owns the audio
if ! command -v pipewire >/dev/null 2>&1 || [[ "$(platform_form_factor "$DOTFILES")" == wsl ]]; then
    exit 0
fi

set -e

conf="${HOME}/.config/pipewire"
mkdir -p "${conf}/pipewire-pulse.conf.d"

# read at pipewire-pulse start only; restarting it here would drop a live call
ln -sfn "${PWD}/roles.conf" "${conf}/pipewire-pulse.conf.d/roles.conf"

install -Dm644 "${PWD}/pipewire-chain@.service" "${HOME}/.config/systemd/user/pipewire-chain@.service"
systemctl --user daemon-reload

# the eq starts on a fresh install; after that the audio panel's switch owns its enablement
[ -e "${conf}/eq.conf" ] || systemctl --user enable pipewire-chain@eq.service
systemctl --user enable pipewire-chain@lanes.service
for chain in lanes eq; do
    ./chains.sh "${chain}" >"${conf}/${chain}.conf.new"
    if cmp -s "${conf}/${chain}.conf.new" "${conf}/${chain}.conf"; then
        rm "${conf}/${chain}.conf.new"
        action=start
    else
        mv "${conf}/${chain}.conf.new" "${conf}/${chain}.conf"
        action=restart
    fi
    if systemctl --user is-enabled -q "pipewire-chain@${chain}.service"; then
        systemctl --user "${action}" "pipewire-chain@${chain}.service"
    fi
done
