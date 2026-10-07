#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source $DOTFILES/scripts/lib/personal.sh
is_personal || exit 0

set -e

PROJECTS="${HOME}/projects"
# github.com/lsck0/<name>; private ones need configs/base/gh's login, which links first (config.sh runs them sorted)
REPOS=(arch-dotfiles homelab)
DIRS=(probe)

# a private repo without credentials fails instead of waiting for a password
export GIT_TERMINAL_PROMPT=0

mkdir -p "$PROJECTS"
# folder icon: .directory for dolphin, gio for nemo
printf '[Desktop Entry]\nIcon=folder-development\n' >"${PROJECTS}/.directory"
if command -v gio >/dev/null 2>&1; then gio set "$PROJECTS" metadata::custom-icon-name folder-development; fi

for dir in "${DIRS[@]}"; do
    mkdir -p "${PROJECTS}/${dir}"
done
for repo in "${REPOS[@]}"; do
    [[ -d "${PROJECTS}/${repo}/.git" ]] && continue
    git clone --recurse-submodules "https://github.com/lsck0/${repo}.git" "${PROJECTS}/${repo}" \
        || echo "projects: cloning ${repo} failed" >&2
done

# a push to github alone must not reach root here through git-sync and config.sh
dotfiles="${PROJECTS}/arch-dotfiles"
if [[ -d "${dotfiles}/.git" ]]; then
    git -C "$dotfiles" config pull.rebase false
    git -C "$dotfiles" config pull.ff only
    git -C "$dotfiles" config merge.verifySignatures true
fi
