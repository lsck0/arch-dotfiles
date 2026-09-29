#!/usr/bin/env bash
# Scaffolds a per-project taskwarrior + timewarrior db and tasks/context/. Safe to re-run.
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

if [[ -d "$task_data" ]]; then
  echo "note: $task_data already exists; reusing it."
fi

# A fresh repo gets one commit of exactly what this script wrote, never `git add -A`.
repo_is_new=0
if git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "note: $target is already inside a git repo; not running 'git init'."
else
  git init -q "$target"
  repo_is_new=1
  echo "initialized a new git repo at $target"
fi

mkdir -p "$task_data/hooks" "$timew_data"
mkdir -p "$tasks_context_dir/research" "$tasks_context_dir/design" "$tasks_context_dir/questions"
# git drops empty dirs; keep the context/ subfolders visible
touch "$tasks_context_dir/research/.gitkeep" "$tasks_context_dir/design/.gitkeep" "$tasks_context_dir/questions/.gitkeep"

# Local and gitignored: devenv's enterShell rewrites it from $DEVENV_ROOT on every entry.
printf 'data.location=%s\nhooks.location=%s\n' "$task_data" "$task_data/hooks" > "$taskrc"

if [[ -e "$hook_dst" ]]; then
  :
elif [[ -f "$hook_src" ]]; then
  install -m 755 "$hook_src" "$hook_dst"
else
  echo "note: $hook_src not found; skipping the timewarrior hook (install the 'timew' package)." >&2
fi

# Plain nix '' string: no ${...} and no doubled single quotes in here.
marker_begin="    # >>> l-agent-task-db taskwarrior env (managed block) >>>"
marker_end="    # <<< l-agent-task-db taskwarrior env (managed block) <<<"
enter_block=$(cat <<'NIX'
    # >>> l-agent-task-db taskwarrior env (managed block) >>>
    mkdir -p "$DEVENV_ROOT/tasks/.task/hooks" "$DEVENV_ROOT/tasks/.timewarrior"
    printf 'data.location=%s\nhooks.location=%s\n' \
      "$DEVENV_ROOT/tasks/.task" "$DEVENV_ROOT/tasks/.task/hooks" > "$DEVENV_ROOT/tasks/.taskrc"
    if [ ! -e "$DEVENV_ROOT/tasks/.task/hooks/on-modify.timewarrior" ] \
      && [ -f /usr/share/doc/timew/ext/on-modify.timewarrior ]; then
      install -m 755 /usr/share/doc/timew/ext/on-modify.timewarrior "$DEVENV_ROOT/tasks/.task/hooks/"
    fi
    export TASKRC="$DEVENV_ROOT/tasks/.taskrc"
    export TIMEWARRIORDB="$DEVENV_ROOT/tasks/.timewarrior"
    # <<< l-agent-task-db taskwarrior env (managed block) <<<
NIX
)

if [[ -f "$devenv_nix" ]]; then
  if grep -qF "$marker_begin" "$devenv_nix" && grep -qF "$marker_end" "$devenv_nix"; then
    python3 - "$devenv_nix" "$enter_block" "$marker_begin" "$marker_end" <<'PY'
import sys
path, block, begin, end = sys.argv[1:5]
text = open(path).read()
start = text.index(begin)
stop = text.index(end, start) + len(end)
new_text = text[:start] + block + text[stop:]
if new_text != text:
    open(path, "w").write(new_text)
PY
    echo "refreshed the managed block in $devenv_nix"
  elif grep -qE "enterShell = ''" "$devenv_nix"; then
    python3 - "$devenv_nix" "$enter_block" <<'PY'
import sys
path, block = sys.argv[1], sys.argv[2]
text = open(path).read()
marker = "enterShell = ''"
insert_at = text.find(marker) + len(marker)
open(path, "w").write(text[:insert_at] + "\n" + block + text[insert_at:])
PY
    echo "patched existing $devenv_nix (inserted into its enterShell block)"
  else
    python3 - "$devenv_nix" "$enter_block" <<'PY'
import sys
path, block = sys.argv[1], sys.argv[2]
text = open(path).read()
idx = text.rfind("}")
if idx == -1:
    sys.exit("no closing '}' found in devenv.nix; patch it by hand")
snippet = "\n  enterShell = ''\n" + block + "\n  '';\n"
open(path, "w").write(text[:idx] + snippet + text[idx:])
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

# first line: identity-init appends to .envrc and must stay last
envrc_devenv_line='use devenv'
if ! grep -qxF "$envrc_devenv_line" "$envrc" 2>/dev/null; then
  envrc_rest=$(cat "$envrc" 2>/dev/null || true)
  printf '%s\n%s' "$envrc_devenv_line" "${envrc_rest:+$envrc_rest$'\n'}" > "$envrc"
fi

if git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  touch "$target/.gitignore"
  for ignored in tasks/.taskrc tasks/.task/ tasks/.timewarrior/ tasks/.poll-backoff; do
    grep -qxF "$ignored" "$target/.gitignore" || printf '%s\n' "$ignored" >> "$target/.gitignore"
  done
  if git -C "$target" ls-files --error-unmatch tasks/.taskrc >/dev/null 2>&1; then
    echo "note: tasks/.taskrc is tracked but now generated; untrack it: git rm --cached tasks/.taskrc" >&2
  fi
fi

# Only for a repo this script just created, committed as the user's own git identity.
if [[ "$repo_is_new" -eq 1 ]]; then
  git -C "$target" add \
    "${devenv_nix#"$target"/}" "${envrc#"$target"/}" .gitignore \
    "${tasks_dir#"$target"/}"
  if git -C "$target" diff --cached --quiet; then
    :
  elif git -C "$target" config user.email >/dev/null && git -C "$target" config user.name >/dev/null; then
    git -C "$target" commit -q -m "Scaffold tasks/ taskwarrior db (l-agent-task-db)"
    echo "committed initial scaffold to the new git repo"
  else
    echo "note: no git user.name/user.email configured; scaffold staged but not committed." >&2
  fi
fi

echo "wrote $taskrc, $task_data/, $timew_data/, $tasks_context_dir/"
echo "use directly with: TASKRC=\"$taskrc\" TIMEWARRIORDB=\"$timew_data\" task ..."
echo "or 'direnv allow' in $target to auto-export both on every cd (requires direnv hooked into your shell rc)."
