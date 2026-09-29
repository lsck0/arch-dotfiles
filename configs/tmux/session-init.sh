#!/usr/bin/env bash
# lay out a fresh session as 1 nvim, 2 claude, 3 zsh

set -euo pipefail

session="$(tmux display-message -p '#{session_id}')"
[[ -n "$session" ]] || exit 0

[[ "$(tmux display-message -p -t "$session" '#{session_windows}')" == 1 ]] || exit 0

# only tms-launched sessions get the layout
[[ "$(tmux show-environment -g TMS_LAUNCH 2>/dev/null)" == "TMS_LAUNCH=1" ]] || exit 0
tmux set-environment -gu TMS_LAUNCH 2>/dev/null || true

cwd="$(tmux display-message -p -t "$session" '#{pane_current_path}')"

# zsh init flushes keys typed before the prompt, so wait for it
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
tmux send-keys -t "${session}:1" 'NVIM_TMS=1 nvim' Enter

tmux new-window -d -t "$session" -c "$cwd" -n claude
claude-trust "$cwd"
wait_prompt "${session}:claude"
tmux send-keys -t "${session}:claude" 'claude --permission-mode auto' Enter

tmux new-window -d -t "$session" -c "$cwd" -n zsh

tmux select-window -t "${session}:1"
