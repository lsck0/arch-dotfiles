#!/usr/bin/env bash

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    exit 0
fi

set -ex

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

mkdir -p ${HOME}/.config ${HOME}/.local/share/color-schemes

ln -sf ${PWD}/color-schemes/pywal.colors ${HOME}/.local/share/color-schemes/pywal.colors

for f in ${FILES}; do
    ln -sf ${PWD}/${f} ${HOME}/.config/${f}
done

for d in ${DIRS}; do
    rm -rf ${HOME}/.config/${d}
    ln -sf ${PWD}/${d} ${HOME}/.config/${d}
done

# Install third-party plasmoids
WIDGET_ID="com.github.prayag2.modernclock"
if ! kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "${WIDGET_ID}"; then
    TMP=$(mktemp -d)
    git clone https://github.com/prayag2/kde_modernclock "${TMP}/kde_modernclock"
    kpackagetool6 -t Plasma/Applet -i "${TMP}/kde_modernclock/package"
    rm -rf "${TMP}"
fi
