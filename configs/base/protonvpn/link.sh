#!/usr/bin/env bash

unit_install auto-vpn.service
# only an identity has a proton account; without NetworkManager (wsl) nmcli monitor ends at once and Restart= loops
if profile_has identity && command -v nmcli >/dev/null 2>&1; then
    systemctl --user enable --now auto-vpn.service
else
    systemctl --user disable --now auto-vpn.service 2>/dev/null || true
fi
