#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

source $DOTFILES/scripts/lib/fetch.sh
source $DOTFILES/scripts/lib/personal.sh

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
    kscreenlockerrc
    ksplashrc
    kwalletrc
    kwinoutputconfig.json
    kwinrc
    kwinrulesrc
    plasma-localerc
    plasma-org.kde.plasma.desktop-appletsrc
    plasmarc
    plasmashellrc
    powerdevilrc
"

DIRS="
    KDE
    kdedefaults
    plasma-workspace
"

mkdir -p "${HOME}/.config" "${HOME}/.local/share/color-schemes" "${HOME}/.local/share/dolphin/view_properties/global"

ln -sfn "${PWD}/color-schemes/pywal.colors" "${HOME}/.local/share/color-schemes/pywal.colors"

mkdir -p "${HOME}/.local/share/applications"
for app in "${PWD}"/applications/*.desktop; do
    ln -sfn "${app}" "${HOME}/.local/share/applications/${app##*/}"
done

# dolphin global view properties
ln -sfn "${PWD}/dolphin/view_properties/global/.directory" "${HOME}/.local/share/dolphin/view_properties/global/.directory"
# dolphin panels: places and information, no folders tree or terminal (kiosk-disabled in dolphinrc); only the dock layout key, since dolphin rewrites the rest of this file (per-screen window geometry) on every close
kwriteconfig6 --file "${HOME}/.local/state/dolphinstaterc" --group State --key State "$(cat "${PWD}/dolphin/dock-state")"

for f in ${FILES}; do
    # a guest's formats follow the locale bootstrap.sh set, not luca's en_US
    [[ "${f}" == plasma-localerc ]] && ! is_personal && continue
    ln -sfn "${PWD}/${f}" "${HOME}/.config/${f}"
done

for d in ${DIRS}; do
    # git drops empty dirs, a link to one would dangle
    [[ -d "${PWD}/${d}" ]] || continue
    # rm right before relink so a failed ln cannot leave the dir gone
    rm -rf "${HOME}/.config/${d}" && ln -sfn "${PWD}/${d}" "${HOME}/.config/${d}" \
        || { echo "plasma/link.sh: failed to relink ${d}" >&2; exit 1; }
done

# third-party plasmoids
WIDGET_ID="com.github.prayag2.modernclock"
if ! kpackagetool6 -t Plasma/Applet -l | grep -qx "${WIDGET_ID}"; then
    TMP=$(mktemp -d)
    fetch_git_pinned https://github.com/prayag2/kde_modernclock 5c86f0f23d2646be7e9872fc5e769bdce259af92 "${TMP}/kde_modernclock"
    kpackagetool6 -t Plasma/Applet -i "${TMP}/kde_modernclock/package"
    rm -rf "${TMP}"
fi
