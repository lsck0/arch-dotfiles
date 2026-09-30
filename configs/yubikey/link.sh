#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -ex

# pam_u2f mapping; empty + nouserok falls back to the password
authdir="${HOME}/.config/Yubico"
mkdir -p "${authdir}"
touch "${authdir}/u2f_keys"
chmod 700 "${authdir}"
chmod 600 "${authdir}/u2f_keys"

# pcscd for ykman; gpg uses its own ccid driver
if systemctl list-unit-files --no-legend pcscd.socket | grep -q .; then
    sudo systemctl enable pcscd.socket || true
fi
