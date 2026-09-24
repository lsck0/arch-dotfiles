#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -x

if ! command -v sshd >/dev/null 2>&1; then
    exit 0
fi

sudo systemctl enable sshd

mkdir -p ${HOME}/.config/systemd/user

ln -sfn ${PWD}/ssh-agent.service ${HOME}/.config/systemd/user/ssh-agent.service

# Authorize the portable identity key (+ this host's own key) BEFORE disabling
mkdir -p ${HOME}/.ssh && chmod 700 ${HOME}/.ssh
touch ${HOME}/.ssh/authorized_keys && chmod 600 ${HOME}/.ssh/authorized_keys
for pub in ../secrets/ssh_publickey.asc ${HOME}/.ssh/id_ed25519.pub; do
    [ -r "$pub" ] || continue
    key=$(cat "$pub")
    grep -qxF "$key" ${HOME}/.ssh/authorized_keys || echo "$key" >> ${HOME}/.ssh/authorized_keys
done

# Key-only login (drop-in disables password auth) — only when a key is actually
if [ -s "${HOME}/.ssh/authorized_keys" ]; then
    sudo ln -sfn "${PWD}/10-hardening.conf" /etc/ssh/sshd_config.d/10-hardening.conf
    sudo sshd -t && sudo systemctl reload sshd
else
    echo "ssh: no authorized_keys yet, keeping password auth to avoid lockout" >&2
fi
