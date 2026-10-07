---
name: l-multi-agent-mode
description: "Live orchestrator: task-planner plans, orchestrator spawns/drives workers (Herdr/Hermes under HERDR_ENV, else Claude Code Agent tool)."
---

# Multi-agent mode (live orchestrator, no task db)

The human gives this instance a prompt. It acts as `l-persona-orchestrator`:
spawns exactly one `l-persona-orchestrator-task-planner` worker to turn that
prompt into a plan, then spawns/drives/gates whatever workers the plan
calls for. This mode is for a single idea worked live, right now: it never
touches taskwarrior. For a self-polling task queue instead, see
`l-multi-agent-task-mode` (spawns workers) or `l-single-agent-task-mode`
(works tasks itself, no spawning).

Load `l-personas` for persona discovery and `l-spec-driven-development` for
the stage shape (sync -> reconcile -> research -> design -> spec, each
reviewed -> spec gate -> phase loop), its file conventions, and its
parallelism budget and 2-implementer cap ("Parallelism and model
choice"). Any worker that designs or writes code (the `l-persona-design-*`
designers, `l-persona-programmer`, `l-persona-reviewer`, `l-persona-tester`)
also loads the `l-style` core plus `l-style-architecture`, since those
personas lean on l-style's principles (primitives, monolith-by-default, no
sentinels, the signature-is-the-product rule) without restating them; a
`l-persona-tester` worker adds `l-style-testing` for the testing order, and
a worker writing latex/math adds `l-style-latex`. A worker never sees a
skill it was not given. Research and audit personas run persona-only.

## Harness detection

```bash
test "${HERDR_ENV:-}" = 1
```

- `HERDR_ENV=1`: running inside a live Herdr session. Workers are Hermes
  panes (the Herdr/Hermes column below). This is the path the skill was
  built on.
- Otherwise, running under Claude Code: workers are spawned with the Agent
  tool (the Claude Code column below). Background agents run concurrently;
  there is no `HERDR_ENV`, no panes, no `herdr` CLI.

Pick the column once from this check and use it throughout; never mix the
two. A `cronjob` has no live Herdr session and no Agent tool, so it cannot
run this skill; if the work must survive across sessions, use a task-mode
skill instead.

## Worker harness policy

One harness per run, many roles: a worker is differentiated only by its
name, its prompt, and which persona skill it carries, never by harness.

- Herdr/Hermes: every worker is `--kind hermes`, never `--kind
  claude`/`codex`/`gemini` (not installed/verified here).
- Claude Code: every worker is an Agent tool call. A worker persona is just
  an Agent prompt that tells the worker to load the `l-persona-*` skill (and
  the l-style parts above) with the Skill tool before doing the work.

**Model choice is the task-planner's job, not this skill's.** The
task-planner checks what is reachable right now and writes the model (and,
on Hermes, provider) for every worker into `PLAN.md`, per
`l-spec-driven-development`'s model-sizing rule: small/cheap models for
research, strong models for design, spec, implementation and review. This
skill reads `PLAN.md` and never re-derives it. Under Hermes the planner
runs `hermes auth list`; under Claude Code the model is the Agent tool's
`model` override (there is no provider concept) and local inference does not
apply. Local inference (`ollama-local`, any local model) is excluded by
default on Hermes; use it only if the human asks for it in this run.

## Workflow

This is `l-spec-driven-development`'s autonomous mode: the human reviews
at input and the spec gate, nowhere else. Under `Merge policy: human` they
also merge each phase PR, without reading its code.

1. Sync (`l-spec-driven-development`): fetch, base branch up to date with
   a clean tree. Spawn one task-planner worker (persona
   `l-persona-orchestrator-task-planner`), prompt it with the human's raw
   ask, and wait for it. It picks the governing spec and writes `PLAN.md`
   into the change's notes directory (`$SPEC_DIR` from here on): which
   personas run, how many, model (and provider on Hermes) each and why,
   dependency order, and whether a phase needs parallel worktrees.
2. Read `PLAN.md`, state it to the human in one or two lines, then execute
   it: spawn each worker the plan calls for, in the order/parallelism it
   specifies. Every worker's task prompt names `$SPEC_DIR` as where its
   output file goes, and the spec directory it amends.
3. Drive reconcile, research, design and spec autonomously, each stage
   followed by a reviewer worker (FAIL -> back to its author), then open
   the spec PR and wait on it (`l-spec-driven-development`, "GitHub"):
   the human merges it or gives feedback (run Feedback, wait again). Never
   ask the human in chat whether it merged; the PR says so.
4. Phase loop (`l-spec-driven-development`, Phase loop): per `SPEC.md`
   Roadmap phase, a new branch off the updated base, implement, open the
   draft PR (trace block, run and revert lines; CI runs on it), then
   review and test against the PR with no human gate. Relay a `FAIL`
   straight back to the programmer worker, who pushes fixes to the same
   PR. Once review, tests and CI pass: `gh pr ready`, then the project's
   merge policy: merge it, or ask the human and wait on the PR. Clean up
   the branch, sync the base, next phase. A spec gap that contradicts a
   signed-off requirement is the one exception: open it as a spec PR and
   wait on it.
5. Report COMPLETE after the last phase merged: requirement IDs built,
   every PR, every check as passed/failed/not run.

Output files: every worker writes `$SPEC_DIR/<STAGE>-<persona>.md`, where
`<STAGE>` is the canonical file's stem and `<persona>` the persona skill
without its `l-persona-` prefix, e.g. `$SPEC_DIR/RESEARCH-research-market.md`
from `l-persona-research-market`. Before advancing to the next stage,
synthesize a stage's files into the canonical file
`l-spec-driven-development` expects (`RESEARCH.md`, `DESIGN.md`, ...).

## Parallel work in one repo: worktrees

Never point two concurrent workers at the same working tree. Each
concurrent implementer gets its own isolated worktree (see the table);
landing and cleanup are in `l-spec-driven-development` ("Parallel
implementation"). Research/design/review workers only write to `$SPEC_DIR`
and share the main checkout.

## Harness mechanics (one table, both harnesses)

`$SPEC_DIR` is where a worker writes its output file. Name every worker for
its role (`research-market`, `architect`, `programmer`, `tester`, ...):
that is how you target prompts and reads, and how the human reads the team.

| operation | HERDR_ENV=1 (Hermes panes) | Claude Code (Agent tool) |
|---|---|---|
| spawn a worker | `herdr pane split --current --direction right --cwd "$REPO_DIR" --no-focus` (read `.result.pane.pane_id`), then `herdr agent start <name> --kind hermes --pane <id> --timeout 30000 -- -m <model> --provider <prov> -s <persona>[,l-style,l-style-architecture[,l-style-testing]]` | one Agent tool call per worker (`subagent_type` general-purpose, or `fork` to share this context); set `model` to the plan's model; the prompt names the role, tells the worker to load the `l-persona-*` skill (and the l-style parts) and to write its output to `$SPEC_DIR/...` then stop |
| isolate parallel edits | `herdr worktree create`; the worker starts in the worktree root pane (`.result.root_pane.pane_id`) and skips the split | pass `isolation: "worktree"` on the Agent call |
| drive / follow up | `herdr agent prompt <name> "<task, ending in: write to $SPEC_DIR/FILE, then stop>" --wait --timeout 120000` | `SendMessage` to the worker's id/name with its context intact |
| wait for completion | `--wait` blocks until the agent settles; else `herdr agent get <name>` until idle | no polling: background agents run concurrently and a completion notification arrives automatically |
| read a worker's result | `cat "$SPEC_DIR/..."` | `cat "$SPEC_DIR/..."` (the worker wrote a durable file) |
| close a worker | `herdr pane close <pane_id>`; `herdr worktree remove --workspace <id>` once its PR is open | a finished agent exits by itself; stop a stale one with `TaskStop <task_id>`; a `worktree` isolation is auto-cleaned when unchanged |

Tell every worker to write its output to a durable file under `$SPEC_DIR`,
not to pane/chat text: every persona skill already states this discipline.
After a worker settles, read the file directly.

Herdr notes: a bare `--kind hermes` start goes straight to `agent_status:
idle`, unlike native CLIs that show a one-time trust dialog. If a start
times out or returns `agent_not_ready`, inspect with `herdr agent read
<name> --source recent-unwrapped --lines 40` and `herdr agent get <name>`.
Never close a pane or remove a worktree you did not create; never `herdr
server stop`.

## Worker lifecycle

A worker lives for one stage, plus the fix-loop rounds that follow it.
Keep a list of every worker you spawned (name, pane or agent id) in
`$SPEC_DIR/WORKERS.md`, so a resumed run knows what it owns
(`l-multi-agent-task-mode` keeps the same record as `worker:` ticket
annotations).

- **Finished**: its output file is read and the next stage started.
  Close it now, unless the next stage prompts it again (the programmer
  gets the review), and drop it from the list.
- **Stale**: it settles without writing its file after one follow-up, it
  is `blocked` on a dialog, or it is still `working`/`unknown` at its
  timeout (30 minutes for research, design and review, 60 for implement
  and test) with no new output. Read its last output, close it, and spawn
  a fresh worker for the stage. Stale twice on one stage: stop and report.
- **End of run**: close every worker still on the list before the final
  report.

## Pitfalls

- **No live session, no run**: a `cronjob` has neither `HERDR_ENV` nor the
  Agent tool, so this skill cannot run from one.
- **No persistence between chat sessions**: if the work must survive across
  sessions/polls, use `l-multi-agent-task-mode` or `l-single-agent-task-mode`.
- **Pick one harness per run**: never spawn Hermes panes and Agent-tool
  workers in the same run.
