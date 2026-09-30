#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

PROJECTS="${HOME}/projects"
# github.com/lsck0/<name>; private ones need configs/gh's login, which links first (config.sh runs them sorted)
REPOS=(arch-dotfiles homelab nyangine paper)
DIRS=(probe)

# a private repo without credentials fails instead of waiting for a password
export GIT_TERMINAL_PROMPT=0

mkdir -p "$PROJECTS"
# folder icon: .directory for dolphin, gio for nemo
printf '[Desktop Entry]\nIcon=folder-development\n' >"${PROJECTS}/.directory"
command -v gio >/dev/null 2>&1 && gio set "$PROJECTS" metadata::custom-icon-name folder-development || true

for dir in "${DIRS[@]}"; do
    mkdir -p "${PROJECTS}/${dir}"
done
for repo in "${REPOS[@]}"; do
    [[ -d "${PROJECTS}/${repo}/.git" ]] && continue
    git clone --recurse-submodules "https://github.com/lsck0/${repo}.git" "${PROJECTS}/${repo}" \
        || echo "projects: cloning ${repo} failed" >&2
done
