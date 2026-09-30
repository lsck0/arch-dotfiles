#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

TOKEN=../secrets/github
if ! command -v gh >/dev/null 2>&1 || ! grep -qs '^gh[a-z]_' "$TOKEN"; then
    exit 0
fi

set -e

if ! gh auth status >/dev/null 2>&1; then
    gh auth login --with-token <"$TOKEN"
fi
# git over https to github authenticates through gh from here on
gh auth setup-git
