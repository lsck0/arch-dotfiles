#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

gnupgdir="${HOME}/.gnupg"
mkdir -p "${gnupgdir}"
chmod 700 "${gnupgdir}"

target="${gnupgdir}/gpg-agent.conf"
if [ -e "${target}" ] && [ ! -L "${target}" ]; then
    cp -a "${target}" "${target}.pre-yubikey.bak"
fi
ln -sfn "${PWD}/gpg-agent.conf" "${target}"

# reload keeps cached keys
gpgconf --reload gpg-agent || true

# Luca Sandrock key: public half always, the private file from unlocked secrets, card stubs if a YubiKey holds it
GPG_FINGERPRINT=E7501F533316E9AFC6AAE907122F2CB527D1EFE3
gpg --batch --import luca-sandrock.pub.asc
echo "${GPG_FINGERPRINT}:6:" | gpg --import-ownertrust
if grep -qs 'BEGIN PGP PRIVATE KEY' ../secrets/pgp_privatekey.asc; then
    gpg --batch --import ../secrets/pgp_privatekey.asc
fi
gpg --card-status >/dev/null 2>&1 || true
