#!/usr/bin/env bash
# Pull the Claude Code login from ~/.claude into configs/secrets/claude; configs/claude/link.sh seeds a fresh home with it.

set -euo pipefail

REPO="${HOME}/projects/arch-dotfiles"
DEST="${REPO}/configs/secrets/claude"

source "${REPO}/scripts/lib/secrets.sh"

[ -f "${HOME}/.claude/.credentials.json" ] || { echo "no ~/.claude/.credentials.json, run claude and log in first" >&2; exit 1; }
# a locked worktree holds GITCRYPT blobs; writing plaintext into it would stage secrets unencrypted
secret_is_plaintext "${REPO}/configs/secrets/pgp_privatekey.asc" \
    || { echo "configs/secrets is locked, unlock it first" >&2; exit 1; }

umask 077
mkdir -p "${DEST}"
cp -f "${HOME}/.claude/.credentials.json" "${DEST}/credentials.json"
# only the account half of ~/.claude.json, the rest is caches and per-project state
jq '{oauthAccount, userID, hasCompletedOnboarding, lastOnboardingVersion}' "${HOME}/.claude.json" >"${DEST}/account.json"
