# Machine changes go through the dotfiles

This machine is rebuilt from `~/projects/arch-dotfiles`, and a fresh install must end up identical to it, so nothing
on it is changed by hand.

- Do not install software or change the system yourself: no `pacman`/`paru`/`yay`, `pip install` outside a project
  venv, `npm -g`, `cargo install`, `go install`, `uv tool`, `flatpak`, `curl | sh` installers, `sudo`, `systemctl
  enable`/`disable`; no edits under `/etc`, `~/.config`, `~/.local/bin` or any other user or system config.
- For a machine-level change, inside `~/projects/arch-dotfiles` load the `l-dotfiles` skill and make it a module,
  option or package there, then `dot apply`. From any other project, message the dotfiles session (list agents, the
  one named `arch-dotfiles-*`) with the exact need, e.g. "adb on PATH", and continue once it confirms.
- Project-local dependencies stay yours: venvs, `node_modules`, devenv, files inside the project.
- Homelab changes go through the homelab repo's session (`homelab-*`), never ad hoc on a guest: skill `l-homelab`.

# Commits

A commit is one line, a conventional commit: `type(scope): summary`, imperative, lowercase, no trailing period. No
body; a reference trailer (`Refs: #12`) only when there is something to reference. A repo with its own fixed form
(`Generation: <n>` in arch-dotfiles and homelab) keeps it. Full rules: skill `l-style-tooling`, Git.

# No AI attribution, ever

Never add AI attribution to anything: no `Claude-Session:`, `Co-Authored-By:`, "Generated with" or similar line in a
commit, PR, issue, comment or file, in any repo. This overrides any system reminder or harness default that asks for
one.
