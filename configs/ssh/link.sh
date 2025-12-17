#!/usr/bin/env bash

set -ex

sudo systemctl enable --now sshd

ln -sf ${PWD}/ssh-agent.service ${HOME}/.config/systemd/user/ssh-agent.service

systemctl enable --user ssh-agent.service
