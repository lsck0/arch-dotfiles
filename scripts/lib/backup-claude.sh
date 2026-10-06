#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# Pull the Claude Code login from ~/.claude into secrets/claude; configs/programming/claude/link.sh seeds a fresh home with it.

set -euo pipefail

REPO="$DOTFILES"
DEST="${REPO}/secrets/claude"

source "${REPO}/scripts/lib/secrets.sh"

[ -f "${HOME}/.claude/.credentials.json" ] || { echo "no ~/.claude/.credentials.json, run claude and log in first" >&2; exit 1; }
secret_require_unlocked "${REPO}"

umask 077
mkdir -p "${DEST}"
cp -f "${HOME}/.claude/.credentials.json" "${DEST}/credentials.json"
# only the account half of ~/.claude.json, the rest is caches and per-project state
jq '{oauthAccount, userID, hasCompletedOnboarding, lastOnboardingVersion}' "${HOME}/.claude.json" >"${DEST}/account.json"
