# Detecting and scaffolding a task db

Part of `l-agent-task-db`.

- Detect: `TASKRC` env var (auto-exported by devenv+direnv on shell
  entry), or a `<project-root>/tasks/.taskrc` file even when operating
  outside that shell (pass it explicitly: `TASKRC=./tasks/.taskrc task ...`).
- If neither exists, run `taskwarrior-init [project-dir]` (defaults to
  `$PWD`; it wraps this skill's `scripts/scaffold.nu`). It is safe to
  re-run: every step checks before writing and existing db data is never
  touched. It:
  - `git init`s a new repo at the target if it isn't already inside one
    (never touches an existing repo's history);
  - creates `tasks/.task/hooks/`, `tasks/.timewarrior/` and
    `tasks/context/{research,design,questions}/` (each with a `.gitkeep`);
  - writes `tasks/.taskrc` (`data.location`, `hooks.location`) with this
    machine's absolute paths, so the db works before any shell entry;
  - installs the `on-modify.timewarrior` hook if missing, so `task <id>
    start`/`stop` auto-tracks a matching timewarrior interval;
  - creates a NEW `devenv.nix` if none exists, or patches an existing
    one's `enterShell` (adding one if absent), leaving the rest of the
    file untouched. The patch is a managed block that re-running
    refreshes in place. On every shell entry that block regenerates
    `tasks/.taskrc` from `$DEVENV_ROOT`, installs the hook if missing, and
    exports `TASKRC` and `TIMEWARRIORDB` from `$DEVENV_ROOT`, so a fresh
    clone on another machine gets a working db on `cd`;
  - puts `use devenv` first in `.envrc`, creating it if needed;
  - ensures `.gitignore` covers `tasks/.taskrc`, `tasks/.task/`,
    `tasks/.timewarrior/` and `tasks/.poll-backoff` (and warns if
    `tasks/.taskrc` is still tracked from an older scaffold);
  - for a FRESH repo only, stages exactly what it wrote (`devenv.nix`,
    `.envrc`, `.gitignore`, `tasks/`) and commits it as the user's
    configured git identity (no identity configured: staged, not
    committed). Never `git add -A`, so unrelated pre-existing files are
    left for the human.
  Auto-export-on-cd requires `eval "$(direnv hook zsh)"` in the shell rc
  (already wired in this repo's `configs/core/zsh/zshrc`); without it,
  `devenv shell` still works, but not automatically on `cd`.
- One db per root: `taskwarrior-init` on a root that already has one
  reuses it rather than creating a second.

