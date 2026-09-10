#!/usr/bin/env bash
# Makes every skills/l-*/SKILL.md here available to Claude Code, Gemini CLI,
# GitHub Copilot CLI, opencode, and Hermes. Names are prefixed "l-" (Luca) to
# namespace them against builtin/other skills sharing the same
# slash-command space.
#
# Claude, Copilot, opencode, and Hermes discover skills from plain
# directories, so those get a real symlink. Gemini has no filesystem
# convention for this — its own `skills link` command is the supported way
# to register a local path, tracked in its own state instead of the
# filesystem. Every tool is guarded on its binary actually being installed,
# so this stays a no-op (not an error) on a machine that doesn't have all of
# them.

set -ex

mkdir -p "${HOME}/.claude/skills" "${HOME}/.copilot/skills" "${HOME}/.config/opencode/skills" "${HOME}/.hermes/skills"

for dir in "${PWD}"/l-*/; do
  name=$(basename "${dir}")

  if command -v claude >/dev/null 2>&1; then
    ln -sf "${dir%/}" "${HOME}/.claude/skills/${name}"
  fi

  if command -v copilot >/dev/null 2>&1; then
    ln -sf "${dir%/}" "${HOME}/.copilot/skills/${name}"
  fi

  if command -v opencode >/dev/null 2>&1; then
    ln -sf "${dir%/}" "${HOME}/.config/opencode/skills/${name}"
  fi

  # Hermes discovers skills by rglob("SKILL.md") under ~/.hermes/skills/, no
  # registration command needed — a symlinked dir works the same as a real
  # one, same pattern as Claude/Copilot/opencode above.
  if command -v hermes >/dev/null 2>&1; then
    ln -sf "${dir%/}" "${HOME}/.hermes/skills/${name}"
  fi

  # Re-running `gemini skills link` on an already-linked skill is not
  # idempotent — it drops a self-referential symlink inside the *source*
  # directory (i.e. right back in this repo) instead of a no-op. Only call
  # it the first time a skill is registered.
  if command -v gemini >/dev/null 2>&1 && ! gemini skills list 2>/dev/null | grep -qxF "${name} [Enabled]"; then
    gemini skills link "${dir%/}" --scope user --consent
  fi
done

# Defensive cleanup: gemini's own skill discovery has been observed to drop
# a self-referential symlink (skills/l-foo/l-foo -> skills/l-foo) back into
# the *source* directory as a side effect of some `gemini skills` calls —
# reproduced even via `list`, not just `link`, so guarding the `link` call
# above isn't sufficient on its own. Sweep it up unconditionally so this
# repo can never end up tracking that garbage regardless of what triggered
# it.
find "${PWD}" -mindepth 2 -maxdepth 2 -type l -name 'l-*' -delete
