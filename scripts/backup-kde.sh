#!/usr/bin/env bash
# Pull live KDE/Plasma config from ~/.config back into configs/plasma/.

set -ex

REPO="${HOME}/projects/arch-dotfiles/configs/plasma"

FILES="
    baloofilerc
    kactivitymanagerd-statsrc
    kactivitymanagerdrc
    kcminputrc
    kded5rc
    kded6rc
    kdeglobals
    kglobalshortcutsrc
    ksplashrc
    kwinoutputconfig.json
    kwinrc
    kwinrulesrc
    plasma-localerc
    plasma-org.kde.plasma.desktop-appletsrc
    plasmarc
    plasmashellrc
"

DIRS="
    KDE
    kdedefaults
    plasma-workspace
"

in_sync() {
    # true if $1 is a symlink resolving to the same path as $2
    [ -L "$1" ] && [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ]
}

for f in ${FILES}; do
    src="${HOME}/.config/${f}"
    dst="${REPO}/${f}"
    [ -e "${src}" ] || continue
    in_sync "${src}" "${dst}" && continue
    cp -fL "${src}" "${dst}"
done

for d in ${DIRS}; do
    src="${HOME}/.config/${d}"
    dst="${REPO}/${d}"
    [ -e "${src}" ] || continue
    in_sync "${src}" "${dst}" && continue
    rm -rf "${dst}"
    cp -rL "${src}" "${dst}"
done
