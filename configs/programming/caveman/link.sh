#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

source ../../../scripts/lib/fetch.sh

# every agent installs from one pinned checkout, never upstream's head; bump both together
CAVEMAN_URL=https://github.com/JuliusBrussee/caveman.git
CAVEMAN_COMMIT=6571943370f7c9d4de1946481177ee7b306cd8e8
CAVEMAN_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/caveman"
SKILLS_CLI=skills@1.7.0

fetch_git_pinned "$CAVEMAN_URL" "$CAVEMAN_COMMIT" "$CAVEMAN_DIR"

if command -v claude >/dev/null 2>&1; then
    # the marketplace is the checkout itself; an older one by the same name points at github
    if ! claude plugin marketplace list | grep -qF "$CAVEMAN_DIR"; then
        claude plugin marketplace list | grep -qw caveman && claude plugin marketplace remove caveman
        claude plugin marketplace add "$CAVEMAN_DIR"
    fi
    claude plugin install caveman@caveman
fi

if command -v gemini >/dev/null 2>&1; then
    [ -d "${HOME}/.gemini/extensions/caveman" ] \
        || gemini extensions install "$CAVEMAN_URL" --ref "$CAVEMAN_COMMIT" --consent
fi

if command -v node >/dev/null 2>&1 && command -v hermes >/dev/null 2>&1; then
    node "$CAVEMAN_DIR/bin/install.js" --only hermes --non-interactive
fi

if command -v copilot >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
    npx -y "$SKILLS_CLI" add "$CAVEMAN_DIR" --skill '*' -a github-copilot -g --yes
fi
