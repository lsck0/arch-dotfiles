#!/usr/bin/env bash

link_into "${HOME}/.local/share/color-schemes" color-schemes/pywal.colors
link_into "${HOME}/.local/share/applications" applications/*.desktop
# dolphin global view properties
link_into "${HOME}/.local/share/dolphin/view_properties/global" dolphin/view_properties/global/.directory
# dolphin panels: places and information, no folders tree or terminal (kiosk-disabled in dolphinrc); only the dock layout key, since dolphin rewrites the rest of this file (per-screen window geometry) on every close
kwriteconfig6 --file "${HOME}/.local/state/dolphinstaterc" --group State --key State "$(cat "${PWD}/dolphin/dock-state")"

for f in *rc kdeglobals *.json; do
    # someone else's formats follow the locale bootstrap.sh set, not luca's en_US
    [[ "${f}" == plasma-localerc ]] && ! profile_has identity && continue
    link_into "${HOME}/.config" "${f}"
done

for d in KDE kdedefaults plasma-workspace; do
    # git drops empty dirs, a link to one would dangle
    [[ -d "${PWD}/${d}" ]] || continue
    # a real dir plasma made is moved aside, not deleted
    link_dir "${PWD}/${d}" "${HOME}/.config/${d}"
done

# third-party plasmoids (owner decision: plasma keeps modernclock)
WIDGET_ID="com.github.prayag2.modernclock"
if ! kpackagetool6 -t Plasma/Applet -l | grep -qx "${WIDGET_ID}"; then
    TMP=$(mktemp -d)
    fetch_git_pinned https://github.com/prayag2/kde_modernclock 5c86f0f23d2646be7e9872fc5e769bdce259af92 "${TMP}/kde_modernclock"
    kpackagetool6 -t Plasma/Applet -i "${TMP}/kde_modernclock/package"
    rm -rf "${TMP}"
fi
