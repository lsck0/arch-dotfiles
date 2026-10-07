#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source $DOTFILES/scripts/lib/personal.sh

set -e

STORE="${HOME}/.password-store"
SYNCED="${HOME}/sync/password-store"

if ! pass otp --help >/dev/null 2>&1; then
    echo "proton-pass: 'pass otp' unavailable, install pass-otp (see configs/base/proton/README.md)" >&2
fi

# the store lives in ~/sync, the only backed-up place outside git
if is_personal; then
    if [ -d "$STORE" ] && [ ! -L "$STORE" ]; then
        if [ -e "$SYNCED" ]; then
            echo "proton-pass: both ${STORE} and ${SYNCED} exist, merge them by hand" >&2
        else
            mkdir -p "$(dirname "$SYNCED")"
            mv "$STORE" "$SYNCED"
        fi
    fi
    if [ ! -e "$STORE" ] || [ -L "$STORE" ]; then
        mkdir -p "$SYNCED"
        ln -sfn "$SYNCED" "$STORE"
    fi
fi

# personal key from configs/base/gnupg; a guest inits by hand
if [ ! -f "${STORE}/.gpg-id" ]; then
    if is_personal && gpg --list-keys "$PERSONAL_GPG_FINGERPRINT" >/dev/null 2>&1; then
        pass init "$PERSONAL_GPG_FINGERPRINT"
    else
        echo "proton-pass: no ~/.password-store yet, run 'pass init <gpg-key-id>' (see configs/base/proton/README.md)" >&2
    fi
fi
