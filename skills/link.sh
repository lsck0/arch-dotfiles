#!/usr/bin/env bash
# Makes every skills/l-*/SKILL.md here available.

set -ex

mkdir -p "${HOME}/.claude/skills" "${HOME}/.copilot/skills" "${HOME}/.hermes/skills"

for dir in "${PWD}"/l-*/; do
  name=$(basename "${dir}")

  if command -v claude >/dev/null 2>&1; then
    ln -sf "${dir%/}" "${HOME}/.claude/skills/${name}"
  fi

  if command -v copilot >/dev/null 2>&1; then
    ln -sf "${dir%/}" "${HOME}/.copilot/skills/${name}"
  fi

  if command -v hermes >/dev/null 2>&1; then
    ln -sf "${dir%/}" "${HOME}/.hermes/skills/${name}"
  fi

  if command -v gemini >/dev/null 2>&1 && ! gemini skills list 2>/dev/null | grep -qxF "${name} [Enabled]"; then
    gemini skills link "${dir%/}" --scope user --consent
  fi
done

# kill recursive links in case they happen (looking at you gemini)
find "${PWD}" -mindepth 2 -maxdepth 2 -type l -name 'l-*' -delete
