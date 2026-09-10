#!/usr/bin/env bash
# Scaffolds a per-project-root taskwarrior (+ timewarrior) instance plus its
# tasks/context/ sibling folder. One instance == one project (taskwarrior's
# own `project:` field is reserved for SUB-grouping inside this one db, e.g.
# sprints — see skills/l-agent-task-db/SKILL.md).
#
# Layout created under <target>/:
#   tasks/.taskrc, tasks/.task/, tasks/.timewarrior/
#   tasks/context/{research,design,questions}/
#   devenv.nix (created or patched) + .envrc, so TASKRC/TIMEWARRIORDB are
#   auto-exported by direnv on `cd`/`direnv allow` — requires
#   `eval "$(direnv hook zsh)"` in the shell rc (already wired in this
#   repo's configs/zsh/zshrc).
#   A git repo, if <target> isn't inside one already (`git init` + one
#   initial commit of just the scaffolded files). An EXISTING repo is
#   never auto-committed to — only its .gitignore gets the new entries.
#
# Usage: scaffold.sh [target-dir]   (defaults to $PWD)
set -euo pipefail

target=${1:-$PWD}
target=$(cd "$target" && pwd)

tasks_dir="$target/tasks"
tasks_context_dir="$tasks_dir/context"
taskrc="$tasks_dir/.taskrc"
task_data="$tasks_dir/.task"
timew_data="$tasks_dir/.timewarrior"
hook_src="/usr/share/doc/timew/ext/on-modify.timewarrior"
hook_dst="$task_data/hooks/on-modify.timewarrior"
devenv_nix="$target/devenv.nix"
envrc="$target/.envrc"

if [[ -f "$taskrc" ]]; then
  echo "error: $taskrc already exists — this project already has a task db." >&2
  exit 1
fi

# --- git repo: init one if <target> isn't already inside a work tree ---
# A fresh repo gets one initial commit of just what THIS script created (not
# a blind `git add -A`, so pre-existing unrelated files in <target> aren't
# silently swept into a commit the user didn't ask for). An existing repo's
# history is never touched — only its .gitignore gains the new entries.
repo_is_new=0
if git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "note: $target is already inside a git repo — not running 'git init'."
else
  git init -q "$target"
  repo_is_new=1
  echo "initialized a new git repo at $target"
fi

mkdir -p "$task_data/hooks" "$timew_data"
mkdir -p "$tasks_context_dir/research" "$tasks_context_dir/design" "$tasks_context_dir/questions"
# git doesn't track empty directories — drop a placeholder so the context/
# subfolders actually show up in the initial commit instead of vanishing
# until the first real file lands in each.
touch "$tasks_context_dir/research/.gitkeep" "$tasks_context_dir/design/.gitkeep" "$tasks_context_dir/questions/.gitkeep"

cat > "$taskrc" <<EOF
data.location=$task_data
hooks.location=$task_data/hooks
EOF

# Wire the timewarrior auto-tracking hook if the system package providing it
# is installed. Silent skip (not a hard failure) otherwise — the task db is
# still fully usable without time tracking.
if [[ -f "$hook_src" ]]; then
  cp "$hook_src" "$hook_dst"
  chmod +x "$hook_dst"
else
  echo "note: $hook_src not found — skipping timewarrior auto-tracking hook (install the 'timew' package to get it)." >&2
fi

# --- devenv.nix wiring: create, or patch an existing one, idempotently ---
marker_begin="    # >>> l-agent-task-db taskwarrior env (managed block) >>>"
marker_end="    # <<< l-agent-task-db taskwarrior env (managed block) <<<"
enter_block="$marker_begin
    export TASKRC=\"\$PWD/tasks/.taskrc\"
    export TIMEWARRIORDB=\"\$PWD/tasks/.timewarrior\"
$marker_end"

if [[ -f "$devenv_nix" ]]; then
  if grep -qF "l-agent-task-db taskwarrior env" "$devenv_nix"; then
    echo "note: $devenv_nix already has the taskwarrior env block — leaving it alone."
  elif grep -qE "enterShell = ''" "$devenv_nix"; then
    python3 - "$devenv_nix" "$enter_block" <<'PY'
import sys
path, block = sys.argv[1], sys.argv[2]
text = open(path).read()
marker = "enterShell = ''"
idx = text.find(marker)
insert_at = idx + len(marker)
new_text = text[:insert_at] + "\n" + block + text[insert_at:]
open(path, "w").write(new_text)
PY
    echo "patched existing $devenv_nix (inserted into its enterShell block)"
  else
    python3 - "$devenv_nix" "$enter_block" <<'PY'
import sys
path, block = sys.argv[1], sys.argv[2]
text = open(path).read()
idx = text.rfind("}")
if idx == -1:
    sys.exit("no closing '}' found in devenv.nix — patch it by hand")
snippet = "\n  enterShell = ''\n" + block + "\n  '';\n"
new_text = text[:idx] + snippet + text[idx:]
open(path, "w").write(new_text)
PY
    echo "patched existing $devenv_nix (added a new enterShell block)"
  fi
else
  cat > "$devenv_nix" <<NIX
{ pkgs, lib, config, inputs, ... }:

{
  enterShell = ''
$enter_block
  '';
}
NIX
  echo "wrote $devenv_nix"
fi

if [[ ! -f "$envrc" ]]; then
  cat > "$envrc" <<'ENVRC'
use devenv
ENVRC
fi

if git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  touch "$target/.gitignore"
  grep -qxF 'tasks/.task/' "$target/.gitignore" || printf 'tasks/.task/\n' >> "$target/.gitignore"
  grep -qxF 'tasks/.timewarrior/' "$target/.gitignore" || printf 'tasks/.timewarrior/\n' >> "$target/.gitignore"
  grep -qxF 'tasks/.poll-backoff' "$target/.gitignore" || printf 'tasks/.poll-backoff\n' >> "$target/.gitignore"
fi

# --- initial commit, only for a repo THIS script just created ---
# Stages exactly what this script wrote (never `git add -A`, so any
# pre-existing untracked files in <target> are left for the human to
# decide about themselves) and commits once so the scaffold isn't left
# sitting as an empty, uncommitted repo.
if [[ "$repo_is_new" -eq 1 ]]; then
  git -C "$target" add \
    "${devenv_nix#$target/}" "${envrc#$target/}" .gitignore \
    "${tasks_dir#$target/}"
  if ! git -C "$target" diff --cached --quiet; then
    git -C "$target" -c user.email="task-scaffold@localhost" -c user.name="l-agent-task-db scaffold" \
      commit -q -m "Scaffold tasks/ taskwarrior db (l-agent-task-db)"
    echo "committed initial scaffold to the new git repo"
  fi
fi

echo "wrote $taskrc, $task_data/, $timew_data/, $tasks_context_dir/"
echo "use directly with: TASKRC=\"$taskrc\" TIMEWARRIORDB=\"$timew_data\" task ..."
echo "or 'direnv allow' in $target to auto-export both on every cd (requires direnv hooked into your shell rc)."
