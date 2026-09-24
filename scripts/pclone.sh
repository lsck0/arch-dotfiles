#!/usr/bin/env bash
# Prompt for a git URL or user/repo, clone it into ~/projects with submodules, then open it in whichever multiplexer launched the popup (tmux or herdr).

set -euo pipefail

PROJECTS="$HOME/projects"

# read from the terminal, not stdin: a popup may hand the command a non-tty
have_gum() { command -v gum >/dev/null 2>&1; }

ask() {  # prompt -> value on stdout, empty/cancel -> exit 0 (close popup)
  local v
  if have_gum; then
    v=$(gum input --prompt "❯ " --placeholder "$1" --width 60 </dev/tty) || exit 0
  else
    read -rp "$1: " v </dev/tty || exit 0
  fi
  [[ -n "$v" ]] || exit 0
  printf '%s' "$v"
}

fail() {  # styled error, then hold the popup so it can be read
  if have_gum; then gum style --foreground 1 "$1" >/dev/tty; else echo "$1" >&2; fi
  read -rp "" _ </dev/tty
  exit 1
}

input="$(ask "git url or user/repo")"

case "$input" in
  *://* | git@*) url="$input" ;;                     # full url, as-is
  */*) url="https://github.com/${input%.git}.git" ;; # user/repo -> github
  *) fail "need a full URL or user/repo" ;;
esac

name="$(basename "${url%.git}")"
dest="$PROJECTS/$name"
if [[ -e "$dest" ]]; then fail "$dest already exists"; fi

if have_gum; then
  gum spin --title "cloning $name..." -- git clone --recurse-submodules "$url" "$dest" || fail "clone failed"
else
  git clone --recurse-submodules "$url" "$dest" || fail "clone failed"
fi

# Open the new repo in the multiplexer that launched this popup.
if [[ -n "${TMUX:-}" ]]; then
  tmux has-session -t "=$name" 2>/dev/null || tmux new-session -d -s "$name" -c "$dest"
  tmux switch-client -t "=$name"
elif [[ -n "${HERDR_SESSION:-}${HERDR_ENV:-}" ]]; then
  herdr-open "$dest" "$name"
else
  echo ">>> cloned to $dest"
  read -rp "" _ </dev/tty
fi
