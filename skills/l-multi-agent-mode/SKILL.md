---
name: l-multi-agent-mode
description: "Live orchestrator for one idea worked now, no task db: a task-planner worker plans, the orchestrator spawns and drives persona workers (Hermes panes under HERDR_ENV, else Claude Code Agent calls) through research, design, spec and phased implementation. Load when the user asks for a multi-agent or orchestrated run on something to be done in this session. Self-polling queue instead: l-multi-agent-task-mode (spawns workers) or l-single-agent-task-mode (works tickets itself)."
---

# Multi-agent mode (live orchestrator, no task db)

The human gives this instance a prompt. It acts as `l-persona-orchestrator`: it spawns exactly one
`l-persona-orchestrator-task-planner` worker to turn the prompt into a plan, then spawns, drives and gates the workers
the plan calls for. It is for a single idea worked live and never touches taskwarrior; work that must survive across
sessions belongs to `l-multi-agent-task-mode` or `l-single-agent-task-mode`.

Load first:

- `l-personas` for persona discovery;
- `l-spec-driven-development` for the stage shape (sync, reconcile, research, design, spec, each reviewed, the spec
  gate, the phase loop), its file conventions, and the parallelism budget with its 2-implementer cap;
- [references/harness.md](references/harness.md): harness detection, the worker policy, model choice, the mechanics
  table and the worker lifecycle. Live mode reads the model from `PLAN.md`, may `fork` a worker, writes outputs to
  `$SPEC_DIR`, and records workers in `$SPEC_DIR/WORKERS.md`.

## Workflow

This is `l-spec-driven-development`'s autonomous mode: the human reviews at input and at the spec gate, nowhere else.
Under `Merge policy: human` they also merge each phase PR, without reading its code.

1. Sync: fetch, base branch up to date, clean tree. Spawn one task-planner worker with the human's raw ask and wait.
   It picks the governing spec and writes `PLAN.md` into the change's notes directory (`$SPEC_DIR` from here on):
   which personas run, how many, the model (and provider on Hermes) for each and why, dependency order, and whether a
   phase needs parallel worktrees.
2. Read `PLAN.md`, state it to the human in a line or two, then execute it: spawn each worker in the order and
   parallelism it gives. Every worker's prompt names `$SPEC_DIR` as where its output goes and the spec directory it
   amends.
3. Drive reconcile, research, design and spec autonomously, each stage followed by a reviewer worker (FAIL goes back
   to the author). Then open the spec PR and wait on it (`l-spec-driven-development`, `references/trace-and-github.md`): the human merges it
   or leaves feedback (run Feedback, wait again). Never ask in chat whether it merged; the PR says so.
4. Phase loop, per `SPEC.md` Roadmap phase: a new branch off the updated base, implement, open the draft PR (trace
   block, run and revert lines; CI runs on it), then review and test against the PR with no human gate. Relay a FAIL
   straight to the programmer worker, who pushes fixes to the same PR. Once review, tests and CI pass: `gh pr ready`,
   then the merge policy (merge it, or ask the human and wait on the PR). Clean up the branch, sync the base, next
   phase. The one exception: a spec gap that contradicts a signed-off requirement becomes a spec PR, waited on.
5. Report COMPLETE after the last phase merged: requirement IDs built, every PR, every check as passed, failed or not
   run.

Output files: every worker writes `$SPEC_DIR/<STAGE>-<persona>.md`, `<STAGE>` the canonical file's stem and
`<persona>` the persona skill without `l-persona-`, e.g. `RESEARCH-research-market.md`. Before the next stage,
synthesize a stage's files into the canonical file `l-spec-driven-development` expects (`RESEARCH.md`, `DESIGN.md`,
...).

## Parallel work in one repo

Never point two concurrent workers at the same working tree. Each concurrent implementer gets its own worktree (the
isolate row in the mechanics table); landing and cleanup are in `l-spec-driven-development`, `references/worktrees.md`.
Research, design and review workers only write to `$SPEC_DIR` and share the main checkout.

## Pitfalls

- No live session, no run: a `cronjob` has neither `HERDR_ENV` nor the Agent tool.
- No persistence between chat sessions: use a task-mode skill for work that must survive.
- One harness per run: never mix Hermes panes and Agent-tool workers.
