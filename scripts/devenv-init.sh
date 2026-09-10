#!/usr/bin/env bash
# Scaffolds a starter devenv.nix (+ .envrc) in the current directory, wired
# so entering the shell gets its own isolated taskwarrior + timewarrior db
# via TASKRC/TIMEWARRIORDB — see skills/l-tasks/ for how agents are
# expected to use it. Same .taskrc/.task/.timewarrior shape as
# skills/l-tasks/scripts/scaffold-task-db.sh, but auto-exported by the
# devenv shell instead of needing per-command env prefixes.
set -euo pipefail

if [[ -f devenv.nix ]]; then
    echo "devenv.nix already exists in $(pwd) — refusing to overwrite." >&2
    exit 1
fi

cat > devenv.nix <<'NIX'
{ pkgs, lib, config, inputs, ... }:

{
  # https://devenv.sh/packages/
  packages = [
    # pkgs.taskwarrior3
    # pkgs.timewarrior
  ];

  # https://devenv.sh/languages/
  # languages.rust.enable = true;
  # languages.python.enable = true;

  # Per-project taskwarrior + timewarrior db: isolated from the global
  # `task`/`timew` dbs and from every other project. First shell entry
  # creates .taskrc (pointing at ./.task/) and ./.timewarrior/ if they
  # don't exist yet, and installs taskwarrior's on-modify.timewarrior hook
  # so `task start`/`stop` auto-tracks a matching timewarrior interval.
  enterShell = ''
    export TASKRC="$PWD/.taskrc"
    export TIMEWARRIORDB="$PWD/.timewarrior"
    if [[ ! -f "$TASKRC" ]]; then
      mkdir -p "$PWD/.task/hooks" "$TIMEWARRIORDB"
      printf 'data.location=%s/.task\nhooks.location=%s/.task/hooks\n' "$PWD" "$PWD" > "$TASKRC"
      hook_src="/usr/share/doc/timew/ext/on-modify.timewarrior"
      if [[ -f "$hook_src" ]]; then
        cp "$hook_src" "$PWD/.task/hooks/on-modify.timewarrior"
        chmod +x "$PWD/.task/hooks/on-modify.timewarrior"
      fi
    fi
  '';

  # https://devenv.sh/tests/
  # enterTest = ''
  #   echo "Running tests"
  # '';
}
NIX

cat > .envrc <<'ENVRC'
use devenv
ENVRC

if [[ -f .gitignore ]]; then
    grep -qxF '.task/' .gitignore || printf '.task/\n' >> .gitignore
    grep -qxF '.timewarrior/' .gitignore || printf '.timewarrior/\n' >> .gitignore
fi

echo "Wrote devenv.nix and .envrc in $(pwd)."
echo "Run 'direnv allow' (or 'devenv shell') to enter — TASKRC/TIMEWARRIORDB will be set on first entry."
