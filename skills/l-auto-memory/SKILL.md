---
name: l-auto-memory
description: "Keep a project's AGENTS.md current with its conventions and key facts."
---

# l-auto-memory

Every project gets an `AGENTS.md` at its root holding the durable, project-
specific knowledge an agent needs to work in it: build/test/run commands,
conventions, architecture landmarks, gotchas. Maintain it automatically as
you work — don't wait to be told.

`AGENTS.md` is project-scoped and git-committed (shared with the team). It
is NOT the built-in per-user memory tool: personal preferences and cross-
project facts stay in memory; anything true about THIS repo that a teammate
or a fresh agent session would also need goes in `AGENTS.md`.

In a project using `l-agent-task-db`, `AGENTS.md` and `tasks/context/` are
also distinct: `tasks/context/` records per-ticket WHY/WHAT (findings and
decisions for one task), while `AGENTS.md` holds the standing project-wide
knowledge (commands, conventions, layout) that outlives any single ticket.
A convention learned while working a ticket goes in `AGENTS.md`; the
reasoning for that ticket's design stays in `tasks/context/`.

Filename: `AGENTS.md` (read by Claude Code, opencode, Codex, and Hermes). If
the repo already uses `CLAUDE.md`, edit that instead of adding a second file
— one source of truth per repo.

## When to write

- Starting in a repo with no `AGENTS.md` (and no `CLAUDE.md`): create one
  from what you discover — the real build/test/lint/run commands (from
  CI/manifests, not guesses), the layout, and the stack.
- You learned something that would have saved you time this session: a
  non-obvious command, a convention, a constraint, a repeated gotcha.
- A convention changed: update the stale line, don't append a contradiction.
- The user states a project rule ("we always X here") — record it.

## What belongs in it

- Build/test/lint/run commands that actually work in this repo.
- Directory/module layout and where the important things live.
- Conventions the code follows: naming, error handling, commit style, branch
  model — reference an in-repo guide (e.g. a style doc) rather than copying.
- Gotchas: setup steps, env vars, flaky areas, things that look wrong but
  aren't.
- Links to the spec/design dirs and any task-db the project uses.

## What stays out

- Personal preferences, cross-project habits, secrets, credentials.
- Anything already generated or in the README — link, don't duplicate.
- Task/TODO state and completed-work logs — those aren't durable knowledge.
- Speculation. Only record what you verified in this repo.

## How to keep it good

- Keep it short and high-signal — it's read into context every session, so
  padding costs tokens every time. A screen or two, not a manual.
- Declarative facts, not narration: "Tests: `just test` (needs devenv
  shell)" beats a paragraph.
- One fact, one place. Editing a value edits it everywhere it's referenced.
- Verify a command before writing it as truth.
- It's git-tracked: commit the update with the change it describes, per the
  repo's own commit convention — don't commit where the repo forbids it
  (e.g. `l-dotfiles`).
