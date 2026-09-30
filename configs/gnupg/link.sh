#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -ex

gnupgdir="${HOME}/.gnupg"
mkdir -p "${gnupgdir}"
chmod 700 "${gnupgdir}"

target="${gnupgdir}/gpg-agent.conf"
if [ -e "${target}" ] && [ ! -L "${target}" ]; then
    cp -a "${target}" "${target}.pre-yubikey.bak"
fi
ln -sfn "${PWD}/gpg-agent.conf" "${target}"

# reload keeps cached keys; the ssh socket binds on next login
gpgconf --reload gpg-agent || true
