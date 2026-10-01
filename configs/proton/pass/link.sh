#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../../scripts/lib/personal.sh

if ! command -v pass >/dev/null 2>&1; then
    exit 0
fi

set -e

if ! pass otp --help >/dev/null 2>&1; then
    echo "proton-pass: 'pass otp' unavailable, install pass-otp (see configs/proton/README.md)" >&2
fi

# personal key from configs/gnupg; a guest inits by hand
GPG_FINGERPRINT=E7501F533316E9AFC6AAE907122F2CB527D1EFE3
if [ ! -d "${HOME}/.password-store" ]; then
    if is_personal && gpg --list-keys "$GPG_FINGERPRINT" >/dev/null 2>&1; then
        pass init "$GPG_FINGERPRINT"
    else
        echo "proton-pass: no ~/.password-store yet, run 'pass init <gpg-key-id>' (see configs/proton/README.md)" >&2
    fi
fi
