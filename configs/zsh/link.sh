#!/usr/bin/env bash

set -ex

sudo git clone https://github.com/chhlga/zsh-opencode-plugin.git /usr/share/oh-my-zsh/custom/plugins/zsh-opencode-ai

ln -sf ${PWD}/zshrc ${HOME}/.zshrc
