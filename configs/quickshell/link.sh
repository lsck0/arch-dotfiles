#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/.config/quickshell ${HOME}/.local/bin
ln -sf ${PWD}/shell.qml ${HOME}/.config/quickshell/shell.qml
ln -sf ${PWD}/theme.json ${HOME}/.config/quickshell/theme.json
ln -sf ${PWD}/Commons ${HOME}/.config/quickshell/Commons
ln -sf ${PWD}/Ui ${HOME}/.config/quickshell/Ui
ln -sf ${PWD}/plugins ${HOME}/.config/quickshell/plugins
ln -sf ${PWD}/services ${HOME}/.config/quickshell/services
ln -sf ${PWD}/scripts ${HOME}/.config/quickshell/scripts
for script in "${PWD}"/scripts/*.sh; do
    ln -sf "$script" "${HOME}/.local/bin/$(basename "$script" .sh)"
done
