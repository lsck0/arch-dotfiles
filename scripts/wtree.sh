#!/usr/bin/env bash
# Branch/worktree selector.

set -euo pipefail

hold() { read -rp "enter to close..." _ </dev/tty; }

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; hold; exit 1; }
repo="$(basename "$root")"

# local branches; typing a new name in fzf creates that branch
branch="$(git -C "$root" for-each-ref --format='%(refname:short)' refs/heads \
    | fzf --prompt="worktree branch> " --print-query --height=100% | tail -1)"
[ -n "${branch:-}" ] || exit 0

# reuse an existing worktree for the branch, else create one
wt="$(git -C "$root" worktree list --porcelain \
    | awk -v b="refs/heads/$branch" '/^worktree /{p=$2} /^branch /{if ($2==b) print p}')"
if [ -z "$wt" ]; then
    wt="$HOME/.worktrees/$repo/$branch"
    mkdir -p "$(dirname "$wt")"
    if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
        git -C "$root" worktree add "$wt" "$branch"
    else
        git -C "$root" worktree add -b "$branch" "$wt"
    fi || { echo "worktree add failed" >&2; hold; exit 1; }
fi

label="${repo}-${branch//\//-}"   # no slashes in a session/workspace label

if [ -n "${HERDR_SESSION:-}${HERDR_ENV:-}" ]; then
    herdr-open "$wt" "$label"      # workspace + 1 nvim, 2 claude, 3 zsh
elif [ -n "${TMUX:-}" ]; then
    tmux has-session -t "=$label" 2>/dev/null || tmux new-session -d -s "$label" -c "$wt"
    tmux switch-client -t "=$label"  # session-created hook lays out the windows
else
    cd "$wt" && exec "$SHELL"
fi
