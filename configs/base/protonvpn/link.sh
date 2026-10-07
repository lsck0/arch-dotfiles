#!/usr/bin/env bash

unit_install auto-vpn.service
# only an identity has a proton account
if profile_has identity; then
    systemctl --user enable --now auto-vpn.service
else
    systemctl --user disable --now auto-vpn.service 2>/dev/null || true
fi
