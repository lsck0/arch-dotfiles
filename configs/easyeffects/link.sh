#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v easyeffects >/dev/null 2>&1; then
    exit 0
fi

set -e

repo="$(cd ../.. && pwd)"

for kind in input output; do
    # pre-8.x links into the repo; the app would migrate and trash them
    old="${HOME}/.config/easyeffects/${kind}"
    if [ -L "${old}" ]; then
        case "$(readlink "${old}")" in
            "${repo}"/*) rm "${old}" ;;
        esac
    fi
done

# presets saved in the app land in the repo
mkdir -p "${HOME}/.local/share/easyeffects"
for kind in input output; do
    dest="${HOME}/.local/share/easyeffects/${kind}"
    # first launch makes real dirs; rmdir refuses if presets are inside
    if [ -d "${dest}" ] && [ ! -L "${dest}" ]; then
        rmdir "${dest}" || { echo "easyeffects: move presets from ${dest} into ${PWD}/${kind}" >&2; exit 1; }
    fi
    ln -sfn "${PWD}/${kind}" "${dest}"
done
