#!/usr/bin/env bash

set -ex

if command -v claude >/dev/null 2>&1; then
    claude plugin marketplace add JuliusBrussee/caveman
    claude plugin install caveman@caveman
fi

if command -v gemini >/dev/null 2>&1; then
    [ -d "${HOME}/.gemini/extensions/caveman" ] || \
        gemini extensions install https://github.com/JuliusBrussee/caveman --consent
fi

if command -v node >/dev/null 2>&1 && { command -v opencode >/dev/null 2>&1 || command -v hermes >/dev/null 2>&1; }; then
    tmp_clone="$(mktemp -d)"
    git clone --depth 1 https://github.com/JuliusBrussee/caveman.git "${tmp_clone}/caveman"
    node "${tmp_clone}/caveman/bin/install.js" --only opencode --only hermes --non-interactive
    rm -rf "${tmp_clone}"
fi

if command -v copilot >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
    npx -y skills add JuliusBrussee/caveman --skill '*' -a github-copilot -g --yes
fi
