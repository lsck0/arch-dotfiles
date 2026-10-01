#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../scripts/lib/personal.sh
is_personal || exit 0

# the platform names its tunnel config in the secrets, toggles/toggle-vpn.sh brings wg0 up
PLATFORM_FILE="../../platforms/$(</etc/hostname).sh"
WIREGUARD=""
# shellcheck source=/dev/null
[[ -f "$PLATFORM_FILE" ]] && source "$PLATFORM_FILE"
if [[ -z "$WIREGUARD" ]] || ! grep -qs '^\[Interface\]' "../secrets/$WIREGUARD"; then
    exit 0
fi

set -e

sudo install -Dm600 "../secrets/$WIREGUARD" /etc/wireguard/wg0.conf
