#!/usr/bin/env bash
# Pull the live gh token into configs/base/secrets/github; configs/base/gh/link.sh logs gh in with it, and gh then authenticates git.

set -euo pipefail

REPO="${HOME}/projects/arch-dotfiles"
DEST="${REPO}/configs/base/secrets/github"

source "${REPO}/scripts/lib/secrets.sh"

secret_require_unlocked "${REPO}"

token=$(gh auth token -h github.com) || { echo "gh is not logged in, run gh auth login first" >&2; exit 1; }
# the same shape configs/base/gh/link.sh accepts, so a broken token never replaces the backup
[[ "$token" =~ ^gh[a-z]_ ]] || { echo "gh auth token returned no token" >&2; exit 1; }

umask 077
printf '%s\n' "$token" >"${DEST}"
