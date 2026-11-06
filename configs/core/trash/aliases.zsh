# a person's rm goes to the trash; an agent's (its marker variable, as sudo-at-terminal checks) stays a plain rm: its
# build trees would fill ~/.local/share/Trash, and trash-cli spins without end on a source deleted under it
[[ -n ${CLAUDECODE-}${AI_AGENT-}${GEMINI_CLI-}${COPILOT_CLI_BINARY_VERSION-} ]] || alias rm="trash -v"
