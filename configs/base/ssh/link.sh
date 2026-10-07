#!/usr/bin/env bash

# the agent for everyone, loading the secrets key only for an identity
unit_install ssh-agent.service ssh-add.service
if profile_has identity; then
    systemctl --user enable ssh-add.service
else
    systemctl --user disable ssh-add.service 2>/dev/null || true
fi

mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
link_into "${HOME}/.ssh" config

# only an identity ships keys to authorize
if profile_has identity; then
    # git-crypt checks it out 0644, ssh and ssh-add refuse a key others can read
    if secret_is_plaintext "$DOTFILES/secrets/ssh_privatekey.asc"; then chmod 600 "$DOTFILES/secrets/ssh_privatekey.asc"; fi
    touch "${HOME}/.ssh/authorized_keys" && chmod 600 "${HOME}/.ssh/authorized_keys"
    for pub in "$DOTFILES/secrets/ssh_publickey.asc" "$DOTFILES"/configs/base/yubikey/ssh-*.pub "${HOME}/.ssh/id_ed25519.pub"; do
        # skips a locked secrets blob as well as a missing file
        secret_is_plaintext "$pub" || continue
        key=$(cat "$pub")
        grep -qxF "$key" "${HOME}/.ssh/authorized_keys" || echo "$key" >> "${HOME}/.ssh/authorized_keys"
    done
fi

# command on PATH, invoked bare by tmux/herdr/nvim/viewers
link_commands sshk.sh
