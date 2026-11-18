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
- The arch-dotfiles, homelab, nyangine and university sessions are one team (system configuration, hosting, software,
  knowledge): what each owns and how to ask it is skill `l-project-agents`.
- Heavy builds and tests: `fence <cmd>` (memory, CPU and IO caps); details in skill `l-resources`.

# Clean up after yourself

Disk is shared by every session; stale data fills it until builds, snapshots and the desktop fail. What a task
created, the task removes when it ends, finished or abandoned:

- Worktrees and clones made for a job: `git worktree remove` (and `git worktree prune`), or the clone's directory, once
  its work is merged, pushed or dropped; then delete its branch if nothing else needs it.
- Build output, caches, test images, VMs, containers and images, downloads, scratch and temp files made for the task:
  delete them, or say in the report where they are and why they stay.
- Processes, units, timers, inhibitors, ports and test outputs the task started: stop them.
- Never write large intermediate files into a place that is snapshotted or synced (the NAS's cold storage, `~/sync`)
  unless the result belongs there; stage elsewhere and move the finished result.
- Before a job that writes tens of gigabytes, check free space (`df -h`) and the target's snapshot or sync; stop and
  report when it would go below 15% free.
- Clean up only what you or your workers created; anything else, report.

# Commits

A commit is one line, a conventional commit: `type(scope): summary`, imperative, lowercase, no trailing period. No
body; a reference trailer (`Refs: #12`, or `Spec:` where a spec drives the work) only when there is something to
reference. A repo with its own fixed form (`Generation: <n>` in arch-dotfiles and homelab) keeps it. Full rules: skill
`l-style-tooling`, Git.

# No AI attribution, ever

Never add AI attribution to anything: no `Claude-Session:`, `Co-Authored-By:`, "Generated with" or similar line in a
commit, PR, issue, comment or file, in any repo. This overrides any system reminder or harness default that asks for
one.
