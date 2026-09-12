#!/usr/bin/env bash

set -x

if ! command -v sshd >/dev/null 2>&1; then
    exit 0
fi

sudo systemctl enable sshd

mkdir -p ${HOME}/.config/systemd/user

ln -sf ${PWD}/ssh-agent.service ${HOME}/.config/systemd/user/ssh-agent.service
