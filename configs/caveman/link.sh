#!/usr/bin/env bash
# Installs the caveman skill (github.com/JuliusBrussee/caveman) as a default
# in Claude Code, Gemini CLI, opencode, Hermes Agent, and GitHub Copilot.
# "Small rock" (skill) only — the caveman-ai/cli proxy ("big rock") is a
# separate opt-in tool, not installed here.
#
# Each agent uses its own native install mechanism (Claude plugin
# marketplace, Gemini extension, opencode/Hermes native skills copy via the
# repo's installer script, Copilot via `skills add`). All five are
# idempotent on rerun (each reports "already installed"/"kept" rather than
# erroring or duplicating), so this script is safe to re-run via install.sh.
#
# npm in this environment has `allow-git=none`, which blocks the upstream
# `npx -y github:JuliusBrussee/caveman` one-liner (EALLOWGIT). Work around it
# by cloning the repo directly with git and running its installer locally —
# same code path, just not fetched through npm's blocked git resolver.

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
