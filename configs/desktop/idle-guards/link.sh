#!/usr/bin/env bash

# the units run the guards through this link
ln -sfn "${PWD}" "${HOME}/.config/idle-guards"
unit_install idle-guard-media.service idle-guard-ssh.service
systemctl --user enable idle-guard-media.service idle-guard-ssh.service
