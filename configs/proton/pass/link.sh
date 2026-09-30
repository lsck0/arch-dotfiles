#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v pass >/dev/null 2>&1; then
    exit 0
fi

set -e

if ! pass otp --help >/dev/null 2>&1; then
    echo "proton-pass: 'pass otp' unavailable, install pass-otp (see configs/proton/README.md)" >&2
fi

if [ ! -d "${HOME}/.password-store" ]; then
    echo "proton-pass: no ~/.password-store yet, run 'pass init <gpg-key-id>' (see configs/proton/README.md)" >&2
fi
