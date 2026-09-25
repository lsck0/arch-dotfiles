#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    exit 0
fi

set -ex

FILES="
    baloofilerc
    kactivitymanagerd-statsrc
    kactivitymanagerdrc
    dolphinrc
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

mkdir -p "${HOME}/.config" "${HOME}/.local/share/color-schemes" "${HOME}/.local/share/dolphin/view_properties/global"

ln -sfn "${PWD}/color-schemes/pywal.colors" "${HOME}/.local/share/color-schemes/pywal.colors"

# Dolphin global view properties (Details view, folders-first, remembered hidden toggle).
ln -sfn "${PWD}/dolphin/view_properties/global/.directory" "${HOME}/.local/share/dolphin/view_properties/global/.directory"

for f in ${FILES}; do
    ln -sfn "${PWD}/${f}" "${HOME}/.config/${f}"
done

for d in ${DIRS}; do
    # rm only right before the relink so a failed ln can't leave the dir gone.
    rm -rf "${HOME}/.config/${d}" && ln -sfn "${PWD}/${d}" "${HOME}/.config/${d}" \
        || { echo "plasma/link.sh: failed to relink ${d}" >&2; exit 1; }
done

# Install third-party plasmoids
WIDGET_ID="com.github.prayag2.modernclock"
if ! kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "${WIDGET_ID}"; then
    TMP=$(mktemp -d)
    git clone https://github.com/prayag2/kde_modernclock "${TMP}/kde_modernclock"
    kpackagetool6 -t Plasma/Applet -i "${TMP}/kde_modernclock/package"
    rm -rf "${TMP}"
fi
