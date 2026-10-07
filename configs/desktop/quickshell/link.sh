#!/usr/bin/env bash

# a real dir left by quickshell itself would swallow the link
rm -rf "${HOME}/.config/quickshell"
ln -sfn "${PWD}" "${HOME}/.config/quickshell"
link_commands scripts/*.sh
