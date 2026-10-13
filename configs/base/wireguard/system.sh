#!/usr/bin/env bash
# the platform names its tunnel config in the admin's secrets (WIREGUARD), scripts/toggles/toggle-vpn.sh brings wg0 up

CONF=/etc/wireguard/wg0.conf
INTERFACE=wg0

# only the machine fact removes it: a run without secrets never undoes one with them
if [[ -z "$WIREGUARD" ]]; then
    if [[ -e "$CONF" ]]; then
        # only the config the dotfiles placed; a wg0.conf made by hand stays
        if [[ "$(sha256sum <"$CONF" | cut -d' ' -f1)" == "$(written_hash "$CONF")" ]]; then
            wg-quick down "$INTERFACE" 2>/dev/null || true
            rm -f "$CONF"
        fi
    fi
    exit 0
fi
[[ "$WIREGUARD" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "wireguard: WIREGUARD '$WIREGUARD' is not a secrets file name" >&2; exit 1; }

secret="$DOTFILES_SECRETS/$WIREGUARD"
[[ -f "$secret" ]] || exit 0
# data only: wg-quick runs the *Up/*Down hooks as root, and SaveConfig would write back into it
if ! grep -q '^\[Interface\]' "$secret" \
    || grep -qiE '^[[:space:]]*(PreUp|PostUp|PreDown|PostDown|SaveConfig)[[:space:]]*=' "$secret"; then
    echo "wireguard: $WIREGUARD is no [Interface] config or carries hooks/SaveConfig, keeping $CONF" >&2
    exit 1
fi
# file_update: a wg0.conf made by hand is preserved first
file_update "$secret" "$CONF" 600 || true
