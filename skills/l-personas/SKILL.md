---
name: l-personas
description: "Persona system: domain-specific instructions layered onto an agent. Load before non-trivial work to pick a matching l-persona-* skill, or when a mode skill spawns persona workers."
---

# l-personas

A persona is a `l-persona-<name>` skill: a focused set of instructions for
one domain (research, design, implementation, review, ...) that narrows
how an agent does a task, not a separate agent.

Before starting non-trivial work, check if a persona matches the domain
and load it. Discover the current set dynamically instead of hardcoding
a list, so a new persona shows up with zero changes elsewhere: list the
installed skills whose name starts with `l-persona-` (Hermes:
`skills_list()`; Claude Code: the skill listing in context).

The installed skill listing (names plus descriptions) is the only source
of truth for what personas exist; read it there, never from a copy kept
here that would drift. Each `l-persona-*` skill's own description says what
it is for.

## Worker personas

Two personas are not loaded by hand for a task. They are the roles an
orchestration mode spawns workers as:

- `l-persona-orchestrator`: owns a multi-agent run, spawns and directs the
  other workers. Loaded by `l-multi-agent-mode` and `l-multi-agent-task-mode`.
- `l-persona-orchestrator-task-planner`: turns a raw ask into a plan
  (PLAN.md live, tickets in task mode). Spawned as a worker by those same
  mode skills.

Everything else is a domain persona you load directly (or that a mode skill
preloads onto a worker) before doing work in that domain.

The department personas (marketing, sales, product, finance, legal,
people, support, comms) deliver documents, not code. Under
`l-spec-driven-development` they follow its Document deliverables path:
the persona writes, a fresh worker of it reviews with `l-persona-legal`
or `l-persona-finance` where law or figures apply, `l-persona-reviewer`
checks. Sending, posting, signing, paying and filing stay Luca's steps.

Fan-out costs tokens, not quality: its budget, caps and model choice live in
`l-spec-driven-development` (Parallelism and model choice).
