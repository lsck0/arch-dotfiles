#!/usr/bin/env bash

TOKEN=$DOTFILES/secrets/github
if ! command -v gh >/dev/null 2>&1 || ! grep -qs '^gh[a-z]_' "$TOKEN"; then
    exit 0
fi

# file storage: plasma swaps the secret service to ksecretd, which hides a gnome-keyring token
if ! gh auth status >/dev/null 2>&1; then
    gh auth login --insecure-storage --with-token <"$TOKEN"
fi
# git over https to github authenticates through gh from here on
gh auth setup-git
