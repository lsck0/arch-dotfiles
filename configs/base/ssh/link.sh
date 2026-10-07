#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source $DOTFILES/scripts/lib/secrets.sh
source $DOTFILES/scripts/lib/personal.sh

set -e

sudo systemctl enable sshd.service

mkdir -p "${HOME}/.config/systemd/user"

ln -sfn "${PWD}/ssh-agent.service" "${HOME}/.config/systemd/user/ssh-agent.service"
is_personal && ln -sfn "${PWD}/ssh-add.service" "${HOME}/.config/systemd/user/ssh-add.service"
systemctl --user daemon-reload
if is_personal; then
    systemctl --user enable ssh-add.service
else
    systemctl --user disable ssh-add.service 2>/dev/null || true
fi

mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
ln -sfn "${PWD}/config" "${HOME}/.ssh/config"

# only luca ships keys to authorize
if is_personal; then
    # git-crypt checks it out 0644, ssh and ssh-add refuse a key others can read
    secret_is_plaintext $DOTFILES/secrets/ssh_privatekey.asc && chmod 600 $DOTFILES/secrets/ssh_privatekey.asc
    mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
    touch "${HOME}/.ssh/authorized_keys" && chmod 600 "${HOME}/.ssh/authorized_keys"
    for pub in $DOTFILES/secrets/ssh_publickey.asc $DOTFILES/configs/base/yubikey/ssh-*.pub "${HOME}/.ssh/id_ed25519.pub"; do
        # skips a locked secrets blob as well as a missing file
        secret_is_plaintext "$pub" || continue
        key=$(cat "$pub")
        grep -qxF "$key" "${HOME}/.ssh/authorized_keys" || echo "$key" >> "${HOME}/.ssh/authorized_keys"
    done
fi

# hardened baseline for every install: real sshd on knocked 2222, no password, no root password login, so a keyless guest has no remote ssh surface (console login still works)
sudo install -Dm644 10-hardening.conf /etc/ssh/sshd_config.d/10-hardening.conf
# no host keys before sshd's first start, and sshd -t needs them
sudo ssh-keygen -A
sudo sshd -t && sudo systemctl reload-or-restart sshd

# command on PATH, invoked bare by tmux/herdr/nvim/viewers
mkdir -p "$HOME/.local/bin"
ln -sfn "$DOTFILES/configs/base/ssh/sshk.sh" "$HOME/.local/bin/sshk"
