#!/usr/bin/env bash

STORE="${HOME}/.password-store"
SYNCED="${HOME}/sync/password-store"

if ! pass otp --help >/dev/null 2>&1; then
    echo "proton-pass: 'pass otp' unavailable, install pass-otp (see configs/base/proton/README.md)" >&2
fi

# the store lives in ~/sync, the only backed-up place outside git
if profile_has identity; then
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

# the identity's key from configs/base/gnupg; anyone else inits by hand
if [ ! -f "${STORE}/.gpg-id" ]; then
    if profile_has identity && [[ -n "$PROFILE_GPG_FINGERPRINT" ]] && gpg --list-keys "$PROFILE_GPG_FINGERPRINT" >/dev/null 2>&1; then
        pass init "$PROFILE_GPG_FINGERPRINT"
    else
        echo "proton-pass: no ~/.password-store yet, run 'pass init <gpg-key-id>' (see configs/base/proton/README.md)" >&2
    fi
fi
