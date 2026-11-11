---
name: l-incremental-development
description: "Incremental workflow: the agent works as the developer at Luca's keyboard, one task at a time: the smallest change that does it, verified, reported in a line, then the next. No spec, no worker pipeline. Load when Luca hands over tasks one by one or says just iterate, just do it, no specs. Breadth first instead: l-pottery-development; a specced, phased change: l-spec-driven-development."
---

# l-incremental-development

The agent is the developer Luca would otherwise be: he names a task, it gets done, he names the next. The loop is short
and the system stays working after every step. This is the default for live projects and for asks that arrive one at
a time in chat.

The three ways of working, pick by the ask:

| way | shape | skill |
|---|---|---|
| spec-driven | research, a phased spec, each phase a revertible PR | `l-spec-driven-development` |
| pottery | throw everything on, then refine and refine | `l-pottery-development` |
| incremental | one task at a time, as the developer at the keyboard | this skill |

## The loop

1. **Take one task.** A new ask that arrives mid-task is queued and done next, unless it says stop or changes the
   current one.
2. **Find the cause or the place.** Read the code and the live state first; no change on a guess.
3. **Smallest change that does it.** Fix the root, not the symptom; touch only what the task needs; follow `l-style`
   and the repo's own conventions.
4. **Verify it yourself.** Build, run the relevant tests, check the running system or a screenshot. What could not be
   verified is said plainly, with the one check that would.
5. **Report in a line or two:** what was wrong, what changed, how it was checked. Then the next task.

## Rules

- No spec stage, no `specs/` amendments, no worker pipeline unless Luca asks for them; design goes into the change and
  its commit. A task that turns out to need a real design is said so, with the choice to switch to
  `l-spec-driven-development`.
- Keep the system working after every task: nothing half-wired, nothing that waits on a later task to be safe.
- Commits follow the repo: where agents may not commit (arch-dotfiles, homelab), leave a clean, lint-passing tree and
  name the changed files; where Luca said "just iterate", do not ask about committing.
- A scope freeze holds: when Luca says no new features, turn ideas into polish of what exists or drop them.
- A gap in a dependency another session owns goes to that session with the exact need; stub that piece and continue.
- Where the work stands goes in the repo's `TODO.md`, not agent memory (`l-auto-memory`).
- Luca's machine stays his: no windows on his screens, no restarts of his apps without need, heavy work at low priority
  (`l-resources`).
