#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source $DOTFILES/scripts/lib/personal.sh

set -e

if ! pass otp --help >/dev/null 2>&1; then
    echo "proton-pass: 'pass otp' unavailable, install pass-otp (see configs/base/proton/README.md)" >&2
fi

# personal key from configs/base/gnupg; a guest inits by hand
GPG_FINGERPRINT=E7501F533316E9AFC6AAE907122F2CB527D1EFE3
if [ ! -d "${HOME}/.password-store" ]; then
    if is_personal && gpg --list-keys "$GPG_FINGERPRINT" >/dev/null 2>&1; then
        pass init "$GPG_FINGERPRINT"
    else
        echo "proton-pass: no ~/.password-store yet, run 'pass init <gpg-key-id>' (see configs/base/proton/README.md)" >&2
    fi
fi
