---
name: l-multi-agent-mode
description: "Live orchestrator: task-planner plans, orchestrator spawns/drives Herdr workers."
---

# Multi-agent mode (live orchestrator, no task db)

The human gives this instance a prompt. It acts as `l-persona-orchestrator`:
spawns exactly one `l-persona-orchestrator-task-planner` worker to turn that
prompt into a plan, then spawns/drives/gates whatever workers the plan
calls for as Herdr panes. This mode is for a single idea worked live, right
now: it never touches taskwarrior. For a self-polling task queue instead,
see `l-multi-agent-task-mode` (spawns workers) or `l-single-agent-task-mode`
(works tasks itself, no spawning).

Load `l-personas` for persona discovery and `l-spec-driven-development` for
the stage shape (sync -> reconcile -> research -> design -> review ->
spec -> spec gate -> phase loop), its file conventions, and its
parallelism budget and 2-implementer cap ("Parallelism and model
choice"). Preload `l-style` alongside any worker that designs or writes
code (the `l-persona-design-*` designers, `l-persona-programmer`,
`l-persona-reviewer` and `l-persona-tester`), since those personas lean
on l-style's principles (primitives, monolith-by-default, no sentinels,
signature-is-the-product, the testing order) without restating them.
`-s` takes a comma-separated list, e.g.
`-s l-persona-design-architecture,l-style`; a worker never sees the skill
otherwise. Research and audit personas run persona-only.

## Precondition

```bash
test "${HERDR_ENV:-}" = 1
```
Stop and tell the user if not running inside Herdr.

## Worker policy

Every worker is a **Hermes harness** (`--kind hermes`): never `--kind
claude`/`codex`/`gemini`, they aren't installed/verified here.

**Model/provider choice is the task-planner's job, not this skill's.**
The task-planner checks which providers are reachable right now (its own
reachability check) and writes the model/provider for every worker into
`PLAN.md`, per `l-spec-driven-development`'s model-sizing rule:
small/cheap models for research, strong models for design, spec,
implementation and review. This skill reads `PLAN.md` and never
re-derives it: don't run `hermes auth list` yourself, and don't carry a provider choice over from
another machine or an earlier run. Local inference (`ollama-local`, any
local model) is excluded by default on any machine; use it only if the
human asks for it in this run, and then say so in the planner's prompt.

## Workflow

This is `l-spec-driven-development`'s autonomous mode: the human appears
at input, the spec gate, and each phase PR. Nowhere else.

1. Sync (`l-spec-driven-development`): fetch, base branch up to date with
   a clean tree. Spawn one task-planner worker
   (`-s l-persona-orchestrator-task-planner`), prompt it with the human's
   raw ask, `--wait`. It picks the governing spec and writes `PLAN.md`
   into the change's notes directory (`$SPEC_DIR` from here on): which
   personas run, how many, model/provider each and why, dependency order,
   and whether a phase needs parallel worktrees (see below).
2. Read `PLAN.md`, state it to the human in one or two lines, then execute
   it: spawn each worker the plan calls for, in the order/parallelism it
   specifies. Every worker's task prompt names `$SPEC_DIR` as where its
   output file goes, and the spec directory it amends.
3. Drive reconcile, research, design, review and spec autonomously, then
   open the spec PR and gate on it with `clarify`: the human merges it or
   gives feedback (run Feedback, gate again).
4. Phase loop: per `ROADMAP.md` phase, implement -> review -> test with no
   gate inside; relay a `FAIL` straight back to the programmer worker.
   Land the phase as its PR (trace block, run and revert lines), then
   gate with `clarify`: the human looks at the PR and its build, and
   merges or gives feedback. Merged -> sync the base, next phase.
   Feedback -> a fresh programmer worker runs Feedback on that PR, gate
   again.
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
concurrent implementer gets its own Herdr worktree; mechanics, landing
and cleanup are in `l-spec-driven-development` ("Parallel
implementation"). Research/design/review workers only write to
`$SPEC_DIR` and share the main checkout.

## Spawning a worker pane

`$SPEC_DIR` is where the worker writes its output file. A worker in the
main checkout gets a split pane; a worker in its own worktree starts in
the worktree's root pane (`.result.root_pane.pane_id` from `herdr
worktree create`) and skips the split.

```bash
herdr pane split --current --direction right --cwd "$REPO_DIR" --no-focus
# -> read new pane id from .result.pane.pane_id

herdr agent start research-market --kind hermes --pane <pane_id> --timeout 30000 \
  -- -m <model-from-plan> --provider <provider-from-plan> -s l-persona-research-market

# implementer/reviewer/designer/tester workers additionally carry l-style:
herdr agent start programmer --kind hermes --pane <pane_id> --timeout 30000 \
  -- -m <model-from-plan> --provider <provider-from-plan> -s l-persona-programmer,l-style
```
`-m`/`--provider` after `--` set whichever model/provider `PLAN.md`
assigned to this worker; `-s <persona-skill>[,l-style]` is what makes the
worker act as that role.

Verified: a bare `--kind hermes` start goes straight to `agent_status:
idle`, unlike native `claude`/`codex`/`gemini`, which show a one-time
workspace-trust dialog. If a start times out or comes back
`agent_not_ready` anyway:
```bash
herdr agent read <name> --source recent-unwrapped --lines 40
herdr agent get <name>
```

Name every worker for its role (`research-market`, `architect`,
`programmer`, `tester`, ...): that's how you target prompts/reads and how
a human glancing at the Herdr sidebar reads the team.

## Driving a worker

```bash
herdr agent prompt research-market "<task, ending in: write findings to \$SPEC_DIR/RESEARCH-research-market.md, then stop>" --wait --timeout 120000
```
`--wait` blocks until the agent settles. Tell it to write its output to a
durable file under `$SPEC_DIR`, not pane text: every persona skill
already states this as its own output discipline. After it settles, read
the file directly:
```bash
cat "$SPEC_DIR/RESEARCH-research-market.md"
```

## Cleanup

```bash
herdr pane close <pane_id>
herdr worktree remove --workspace <id>   # per worktree, once its PR is open
```
Never close a pane or remove a worktree you did not create; never
`herdr server stop`.

## Pitfalls

- **A `cronjob` cannot do this skill's work**: no live Herdr session, so
  the precondition fails.
- **No persistence between chat sessions**: if the work needs to survive
  across sessions/polls, use `l-multi-agent-task-mode` or
  `l-single-agent-task-mode` instead.
- **Verified working**: hermes-kind panes spawn cleanly with no trust
  dialog, take a prompt via `agent prompt --wait`, and write their
  assigned file back to disk: the whole spawn -> prompt -> durable-file
  loop this skill relies on.
