#!/usr/bin/env bash
# Pull the live gh token into configs/secrets/github; configs/gh/link.sh logs gh in with it, and gh then authenticates git.

set -euo pipefail

REPO="${HOME}/projects/arch-dotfiles"
DEST="${REPO}/configs/secrets/github"

source "${REPO}/scripts/lib/secrets.sh"

# a locked worktree holds GITCRYPT blobs; writing plaintext into it would stage secrets unencrypted
secret_is_plaintext "${REPO}/configs/secrets/pgp_privatekey.asc" \
    || { echo "configs/secrets is locked, unlock it first" >&2; exit 1; }

token=$(gh auth token -h github.com) || { echo "gh is not logged in, run gh auth login first" >&2; exit 1; }
# the same shape configs/gh/link.sh accepts, so a broken token never replaces the backup
[[ "$token" =~ ^gh[a-z]_ ]] || { echo "gh auth token returned no token" >&2; exit 1; }

umask 077
printf '%s\n' "$token" >"${DEST}"
