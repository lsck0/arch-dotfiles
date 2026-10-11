#!/usr/bin/env bash

# the public key file this module ships, imported only for the identity whose fingerprint it holds
PUBLIC_KEY=luca-sandrock.pub.asc

gnupgdir="${HOME}/.gnupg"
mkdir -p "${gnupgdir}"
chmod 700 "${gnupgdir}"

for conf in gpg-agent.conf scdaemon.conf; do
    target="${gnupgdir}/${conf}"
    if [ -e "${target}" ] && [ ! -L "${target}" ]; then
        cp -a "${target}" "${target}.pre-yubikey.bak"
    fi
done
link_into "$gnupgdir" gpg-agent.conf scdaemon.conf

# rendered, not linked: the identity's key is the default for every sign and encrypt-to-self, a user without one has none
gpg_conf="${gnupgdir}/gpg.conf"
rm -f "$gpg_conf"
cp gpg.conf "$gpg_conf"
if profile_has identity && [[ -n "$PROFILE_GPG_FINGERPRINT" ]]; then
    echo "default-key ${PROFILE_GPG_FINGERPRINT}" >>"$gpg_conf"
fi

# reload keeps cached keys; scdaemon reads its config only at start
gpgconf --reload gpg-agent
gpgconf --kill scdaemon

# the identity's key: public half always, the private file from unlocked secrets, card stubs if a YubiKey holds it
if profile_has identity && [[ -n "$PROFILE_GPG_FINGERPRINT" ]]; then
    if gpg --show-keys --with-colons "$PUBLIC_KEY" | grep -qx "fpr:*${PROFILE_GPG_FINGERPRINT}:"; then
        gpg --batch --import "$PUBLIC_KEY"
    fi
    echo "${PROFILE_GPG_FINGERPRINT}:6:" | gpg --import-ownertrust
    if grep -qs 'BEGIN PGP PRIVATE KEY' "$DOTFILES/secrets/pgp_privatekey.asc"; then
        gpg --batch --import "$DOTFILES/secrets/pgp_privatekey.asc"
    fi
    # writes the card stubs when a YubiKey is plugged in, none plugged in is fine
    gpg --card-status >/dev/null 2>&1 || true
fi
