#!/usr/bin/env bash
# Lay out a fresh tmux session as three windows: 1 nvim, 2 claude, 3 zsh.

set -euo pipefail

session="$(tmux display-message -p '#{session_id}')"
[[ -n "$session" ]] || exit 0

[[ "$(tmux display-message -p -t "$session" '#{session_windows}')" == 1 ]] || exit 0

cwd="$(tmux display-message -p -t "$session" '#{pane_current_path}')"

# Wait until the pane's zsh is idle at its prompt before typing. A devenv/direnv
# shell is slow to start, and zsh resets the tty on init, flushing keystrokes
# typed ahead of the prompt (which dropped the nvim/claude launch).
wait_prompt() {
    local target=$1 i last
    for ((i = 0; i < 120; i++)); do
        last=$(tmux capture-pane -p -t "$target" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -1 || true)
        [[ "$last" == *λ* || "$last" == *❯* || "$last" =~ [\$%#][[:space:]]*$ ]] && return 0
        sleep 0.15
    done
}

tmux rename-window -t "${session}:1" nvim
wait_prompt "${session}:1"
tmux send-keys -t "${session}:1" nvim Enter

tmux new-window -d -t "$session" -c "$cwd" -n claude
claude-trust "$cwd"   # skip the workspace trust dialog for this repo
wait_prompt "${session}:claude"
tmux send-keys -t "${session}:claude" 'claude --permission-mode auto' Enter

tmux new-window -d -t "$session" -c "$cwd" -n zsh
# zsh is the window's default shell already; nothing to launch

tmux select-window -t "${session}:1"
