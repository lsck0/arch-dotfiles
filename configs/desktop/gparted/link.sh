#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

GPARTED_DESKTOP_SRC=/usr/share/applications/gparted.desktop
GPARTED_DESKTOP_DEST="${HOME}/.local/share/applications/gparted.desktop"
if [ -f "${GPARTED_DESKTOP_SRC}" ]; then
    mkdir -p "$(dirname "${GPARTED_DESKTOP_DEST}")"
    cp "${GPARTED_DESKTOP_SRC}" "${GPARTED_DESKTOP_DEST}"
    sed -i "s|^Exec=.*gparted.*|Exec=pkexec /usr/bin/gparted %f|" "${GPARTED_DESKTOP_DEST}"
fi
