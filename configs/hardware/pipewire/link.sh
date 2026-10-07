#!/usr/bin/env bash

# pipewire also arrives under wsl, as a dependency of the portals, where wslg owns the audio
if ! command -v pipewire >/dev/null 2>&1 || [[ "$FORM_FACTOR" == wsl ]]; then
    exit 0
fi

conf="${XDG_CONFIG_HOME:-$HOME/.config}/pipewire"

# read at pipewire-pulse start only; restarting it here would drop a live call
link_into "$conf/pipewire-pulse.conf.d" roles.conf

unit_install pipewire-chain@.service

# the eq starts on a fresh install; after that the audio panel's switch owns its enablement
[ -e "$conf/eq.conf" ] || systemctl --user enable pipewire-chain@eq.service
systemctl --user enable pipewire-chain@lanes.service
for chain in lanes eq; do
    ./chains.sh "$chain" >"$conf/$chain.conf.new"
    if cmp -s "$conf/$chain.conf.new" "$conf/$chain.conf"; then
        rm "$conf/$chain.conf.new"
        action=start
    else
        mv "$conf/$chain.conf.new" "$conf/$chain.conf"
        action=restart
    fi
    if systemctl --user is-enabled -q "pipewire-chain@$chain.service"; then
        systemctl --user "$action" "pipewire-chain@$chain.service"
    fi
done
