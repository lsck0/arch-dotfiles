#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -ex

mkdir -p ${HOME}/.config/quickshell ${HOME}/.local/bin
ln -sfn ${PWD}/shell.qml ${HOME}/.config/quickshell/shell.qml
ln -sfn ${PWD}/theme.json ${HOME}/.config/quickshell/theme.json
ln -sfn ${PWD}/Commons ${HOME}/.config/quickshell/Commons
ln -sfn ${PWD}/Ui ${HOME}/.config/quickshell/Ui
ln -sfn ${PWD}/plugins ${HOME}/.config/quickshell/plugins
ln -sfn ${PWD}/services ${HOME}/.config/quickshell/services
ln -sfn ${PWD}/scripts ${HOME}/.config/quickshell/scripts
# The homelab bar widget reads its fleet and links from this checkout.
if [[ ! -d "${HOME}/projects/homelab/.git" ]]; then
    git clone https://github.com/lsck0/homelab.git "${HOME}/projects/homelab" || true
fi
for script in "${PWD}"/scripts/*.sh; do
    ln -sfn "$script" "${HOME}/.local/bin/$(basename "$script" .sh)"
done
