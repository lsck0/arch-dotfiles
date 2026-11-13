# a person's rm goes to the trash; an agent's (zshrc's agent-session) stays a plain rm: its build trees would fill
# ~/.local/share/Trash, and trash-cli spins without end on a source deleted under it
agent-session || alias rm="trash -v"
