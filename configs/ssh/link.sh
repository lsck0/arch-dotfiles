#!/usr/bin/env bash

set -x

sudo systemctl enable sshd

mkdir -p ${HOME}/.config/systemd/user
ln -sf ${PWD}/ssh-agent.service ${HOME}/.config/systemd/user/ssh-agent.service

systemctl enable --user ssh-agent.service
