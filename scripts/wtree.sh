#!/usr/bin/env bash
# Branch/worktree selector. New worktrees follow the layout, as configs/programming/nvim/lua/lib/worktree.lua does:
#   <repo>/.bare + <repo>/branches/<slug>   bare layout of clones-sdd-repos.sh
#   <bare>/<slug>                            worktrees inside a plain bare repo (~/projects/probe)
#   ~/.worktrees/<repo>/<slug>               normal checkout
# Once linked worktrees exist, the dir most of them share wins over all of the above.

set -euo pipefail

hold() { read -rp "enter to close..." _ </dev/tty; }

# plain git from cwd, not --show-toplevel: that fails at a bare root and names branches/main "main"
list="$(git worktree list --porcelain 2>/dev/null)" || { echo "not a git repo" >&2; hold; exit 1; }

# the first entry is the main checkout or the bare repo itself
main="$(awk '/^worktree /{print substr($0, 10); exit}' <<<"$list")"
bare="$(awk '/^$/{exit} $0 == "bare"{print 1}' <<<"$list")"
repo="$(basename "$main")"
[ "$repo" != .bare ] || repo="$(basename "$(dirname "$main")")"

# local and origin branches; typing a new name in fzf creates that branch
branch="$(git for-each-ref --format='%(refname)' refs/heads refs/remotes/origin \
    | awk '{sub(/^refs\/(heads|remotes\/origin)\//, "")} $0 != "HEAD" && !seen[$0]++' \
    | fzf --prompt="worktree branch> " --print-query --height=100% | tail -1)" || true  # fzf exits 1 on a new name
[ -n "${branch:-}" ] || exit 0

# reuse an existing worktree for the branch, else create one
wt="$(awk -v b="refs/heads/$branch" '/^worktree /{p=substr($0, 10)} /^branch /{if (substr($0, 8) == b) print p}' <<<"$list")"
if [ -z "$wt" ]; then
    # ties go to the shallower dir, so one stray nested worktree never becomes the convention
    parent="$(awk '
        /^worktree / { if (++n == 1) next; p = substr($0, 10); sub(/\/[^\/]*$/, "", p); c[p]++
                       if (best == "" || c[p] > c[best] || (c[p] == c[best] && length(p) < length(best))) best = p }
        END { print best }' <<<"$list")"
    slug="${branch//\//-}"   # feat/x is one dir, like clones-sdd-repos.sh's slug_of
    if [ -n "$parent" ]; then
        wt="$parent/$slug"
    elif [ -z "$bare" ]; then
        wt="$HOME/.worktrees/$repo/$slug"
    elif [ "$(basename "$main")" = .bare ]; then
        wt="$(dirname "$main")/branches/$slug"
    else
        wt="$main/$slug"
    fi
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        git worktree add "$wt" "$branch"
    elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        git worktree add --track -b "$branch" "$wt" "origin/$branch"
    else
        git worktree add -b "$branch" "$wt"
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
