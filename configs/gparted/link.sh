#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v gparted >/dev/null 2>&1; then
    exit 0
fi

set -ex

GPARTED_DESKTOP_SRC=/usr/share/applications/gparted.desktop
GPARTED_DESKTOP_DEST="${HOME}/.local/share/applications/gparted.desktop"
if [ -f "${GPARTED_DESKTOP_SRC}" ]; then
    mkdir -p "$(dirname "${GPARTED_DESKTOP_DEST}")"
    cp "${GPARTED_DESKTOP_SRC}" "${GPARTED_DESKTOP_DEST}"
    sed -i "s|^Exec=.*gparted.*|Exec=pkexec /usr/bin/gparted %f|" "${GPARTED_DESKTOP_DEST}"
    update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
fi

if [[ -d /etc/polkit-1/rules.d ]]; then
    sudo ln -sfn ${PWD}/50-gparted-nopasswd.rules /etc/polkit-1/rules.d/50-gparted-nopasswd.rules
fi
