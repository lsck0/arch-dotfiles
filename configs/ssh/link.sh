#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../scripts/lib/secrets.sh
source ../../scripts/lib/personal.sh

if ! command -v sshd >/dev/null 2>&1; then
    exit 0
fi

set -e

sudo systemctl enable sshd

mkdir -p "${HOME}/.config/systemd/user"

ln -sfn "${PWD}/ssh-agent.service" "${HOME}/.config/systemd/user/ssh-agent.service"
ln -sfn "${PWD}/ssh-add.service" "${HOME}/.config/systemd/user/ssh-add.service"
systemctl --user daemon-reload
systemctl --user enable ssh-add.service

mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
ln -sfn "${PWD}/config" "${HOME}/.ssh/config"

# only luca ships keys to authorize
if is_personal; then
    # git-crypt checks it out 0644, ssh and ssh-add refuse a key others can read
    secret_is_plaintext ../secrets/ssh_privatekey.asc && chmod 600 ../secrets/ssh_privatekey.asc
    mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
    touch "${HOME}/.ssh/authorized_keys" && chmod 600 "${HOME}/.ssh/authorized_keys"
    for pub in ../secrets/ssh_publickey.asc ../yubikey/ssh-*.pub "${HOME}/.ssh/id_ed25519.pub"; do
        # skips a locked secrets blob as well as a missing file
        secret_is_plaintext "$pub" || continue
        key=$(cat "$pub")
        grep -qxF "$key" "${HOME}/.ssh/authorized_keys" || echo "$key" >> "${HOME}/.ssh/authorized_keys"
    done
fi

# hardened baseline for every install: real sshd on knocked 2222, no password, no root password login.
# a keyless guest then has no remote ssh surface (console login still works)
sudo ln -sfn "${PWD}/10-hardening.conf" /etc/ssh/sshd_config.d/10-hardening.conf
sudo sshd -t && sudo systemctl reload sshd
