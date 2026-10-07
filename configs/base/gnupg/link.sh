#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source $DOTFILES/scripts/lib/personal.sh

set -e

gnupgdir="${HOME}/.gnupg"
mkdir -p "${gnupgdir}"
chmod 700 "${gnupgdir}"

for conf in gpg-agent.conf scdaemon.conf; do
    target="${gnupgdir}/${conf}"
    if [ -e "${target}" ] && [ ! -L "${target}" ]; then
        cp -a "${target}" "${target}.pre-yubikey.bak"
    fi
    ln -sfn "${PWD}/${conf}" "${target}"
done

# rendered, not linked: luca's key is the default for every sign and encrypt-to-self, a guest has none
gpg_conf="${gnupgdir}/gpg.conf"
rm -f "$gpg_conf"
cp gpg.conf "$gpg_conf"
is_personal && echo "default-key ${PERSONAL_GPG_FINGERPRINT}" >>"$gpg_conf"

# reload keeps cached keys; scdaemon reads its config only at start
gpgconf --reload gpg-agent
gpgconf --kill scdaemon

# Luca Sandrock key: public half always, the private file from unlocked secrets, card stubs if a YubiKey holds it
if is_personal; then
    gpg --batch --import luca-sandrock.pub.asc
    echo "${PERSONAL_GPG_FINGERPRINT}:6:" | gpg --import-ownertrust
    if grep -qs 'BEGIN PGP PRIVATE KEY' $DOTFILES/secrets/pgp_privatekey.asc; then
        gpg --batch --import $DOTFILES/secrets/pgp_privatekey.asc
    fi
    # writes the card stubs when a YubiKey is plugged in, none plugged in is fine
    gpg --card-status >/dev/null 2>&1 || true
fi
