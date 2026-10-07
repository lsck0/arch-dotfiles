#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# Pull live KDE/Plasma config from ~/.config back into configs/desktop/plasma/.

set -euo pipefail

REPO="$DOTFILES/configs/desktop/plasma"

DIRS="
    KDE
    kdedefaults
    plasma-workspace
"

in_sync() {
    # true if $1 is a symlink resolving to the same path as $2
    [ -L "$1" ] && [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ]
}

# the repo's own files, so this cannot drift from plasma/link.sh's list
for dst in "${REPO}"/*rc "${REPO}"/kdeglobals "${REPO}"/*.json; do
    src="${HOME}/.config/${dst##*/}"
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
