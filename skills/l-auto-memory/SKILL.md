---
name: l-auto-memory
description: "Keep a project's agent knowledge current: a per-project skills/ folder of project-specific workflows (how to use the project, develop on it, use its tools, find its credentials) and the AGENTS.md index that lists them. Load when working in any project meant to last."
---

# l-auto-memory

Every project carries what an agent needs to work in it, maintained
automatically as you work; don't wait to be told. Two parts:

- `skills/<name>/SKILL.md`: one skill per project-specific workflow.
- `AGENTS.md` at the root: the standing facts plus an index of those
  skills, so every agent session loads the index into context and opens
  the skill a task needs.

Three stores, three jobs, never mixed:

- `specs/` (`l-spec-driven-development`): what the system does and how it
  is built.
- `skills/` and `AGENTS.md` (this skill): how to work on and with the
  project.
- `tasks/context/` (`l-agent-task-db`): the findings and decisions of one
  ticket.

A convention learned while working a ticket goes into a skill or
`AGENTS.md`; the reasoning for that ticket's design stays in
`tasks/context/`. Personal preferences and cross-project habits stay in
the per-user memory, never in the repo.

## Project skills

A project skill explains one core workflow the way a teammate would show
it: the exact commands, in order, and what to check after each. Typical
ones:

- Using the project: running it, its CLI or API, its main use cases.
- Developing on it: build, test, debug, profile, release, the edit-run
  loop, adding a module or a plugin.
- Tools: how this project uses a specific tool (a simulator, a fuzzer, a
  deploy target, a database console).
- Access: how to reach a service, a server, a dashboard, and where its
  credentials live (the `pass` entry, the `secrets/` path, the env var
  name). Never the credential itself.

Layout and format:

- `skills/<name>/SKILL.md`, `<name>` lowercase kebab-case, named for the
  workflow (`run-tests`, `release`, `access-staging`). Supporting scripts
  sit next to it in the same directory.
- Frontmatter `name:` equal to the directory and a one-line
  `description:` saying what it covers and when to load it; the index
  copies that line.
- Symlink `.claude/skills -> ../skills`, so Claude Code discovers the
  skills natively; other harnesses reach them through the index.
- One workflow per skill. A skill that grows a second workflow splits.

## AGENTS.md

`AGENTS.md` is read by opencode, Codex and Hermes. Claude Code reads
`CLAUDE.md`, so a project with `AGENTS.md` also has a one-line `CLAUDE.md`
containing `@AGENTS.md`. If the repo already uses only `CLAUDE.md`, edit
that instead. One source of truth either way.

It holds:

- The skills index, first:
  ```
  ## Skills

  Load the skill a task needs from `skills/<name>/SKILL.md`.

  | skill | use it for |
  |---|---|
  | `run-tests` | running the suites, reading a failing seed, coverage |
  | `access-staging` | reaching staging, where its credentials live |
  ```
- Build/test/lint/run commands that actually work, the one-liners only;
  anything longer is a skill.
- Layout: where the important things live.
- Conventions: naming, error handling, commit style, branch model,
  `Merge policy:` and `Reviewer:` (`l-spec-driven-development`).
  Reference an in-repo guide rather than copying it.
- Gotchas: setup steps, env vars, flaky areas, things that look wrong but
  aren't.
- Links to `specs/INDEX.md` and any task db.

## When to write

- Starting in a repo with no `AGENTS.md`: create it, the `CLAUDE.md`
  import, `skills/` and the `.claude/skills` symlink from what you
  discover: the real commands (from CI and manifests, not guesses), the
  layout, the stack.
- You performed a workflow that took more than one obvious command, or
  that cost you time to work out: write or update its skill and the index
  row.
- You found how to reach something, or where its credentials are: an
  access skill.
- A convention or command changed: update the stale skill or line in
  the same commit as the change; never append a contradiction.
- The user states a project rule ("we always X here"): record it.

## What stays out

- Secrets and credential values. Locations only.
- Personal preferences and cross-project habits.
- Anything generated or already in the README or specs: link it.
- Task state and completed-work logs.
- Speculation. Only record what you verified in this repo.

## How to keep it good

- `AGENTS.md` is read into context every session: a screen or two,
  declarative, no narration. Detail belongs in the skills, which load
  only when needed.
- Every index row matches a skill directory and every skill has a row.
  Remove both together.
- Verify a command before writing it as truth.
- One fact, one place.
- Commit skill and index changes with the change they describe, per the
  repo's own commit convention; don't commit where the repo forbids it
  (e.g. `l-dotfiles`).
