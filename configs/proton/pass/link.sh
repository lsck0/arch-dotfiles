#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v pass >/dev/null 2>&1; then
    exit 0
fi

set -ex

# pass-otp adds the `pass otp` subcommand; nothing to symlink, just verify it loaded.
if command -v pass >/dev/null 2>&1 && ! pass otp --help >/dev/null 2>&1; then
    echo "proton-pass: 'pass otp' unavailable — install pass-otp (see configs/proton/README.md)" >&2
fi

# The store itself is initialized manually with your GPG key (see configs/proton/README.md);
# link.sh never touches secrets. Just guidance if the store is not set up yet.
if [ ! -d "${HOME}/.password-store" ]; then
    echo "proton-pass: no ~/.password-store yet — run 'pass init <gpg-key-id>' (see configs/proton/README.md)" >&2
fi
