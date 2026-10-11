#!/usr/bin/env bash

# login shell is set at user creation (bootstrap, adduser-dotfiles), not here
mkdir -p "${HOME}/.zsh/completions"
ln -sfn "${PWD}/zshrc" "${HOME}/.zshrc"
# a command, not a zsh function: agents run builds from non-interactive shells
link_commands fence.sh
# systemd's user manager hands it to every unit and graphical app, zshrc to tty and ssh logins
link_into "${XDG_CONFIG_HOME:-$HOME/.config}/environment.d" no-telemetry.conf
