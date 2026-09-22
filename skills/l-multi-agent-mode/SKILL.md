---
name: l-multi-agent-mode
description: "Live orchestrator: task-planner plans, orchestrator spawns/drives Herdr workers."
---

# Multi-agent mode (live orchestrator, no task db)

The human gives this instance a prompt. It acts as `l-persona-orchestrator`:
spawns exactly one `l-persona-orchestrator-task-planner` worker to turn that
prompt into a plan, then spawns/drives/gates whatever workers the plan
calls for as Herdr panes. This mode is for a single idea worked live, right
now — it never touches taskwarrior. For a self-polling task queue instead,
see `l-multi-agent-task-mode` (spawns workers) or `l-single-agent-task-mode`
(works tasks itself, no spawning).

Load `l-personas` for persona discovery and `l-spec-driven-development` for
the stage shape (sync -> reconcile -> research -> design -> review ->
spec -> spec gate -> phase loop) and its file conventions. Preload `l-style` alongside any
worker that designs or writes code — the `l-persona-design-*` designers,
`l-persona-programmer`, and `l-persona-reviewer` — since those personas
lean on l-style's principles (primitives, monolith-by-default, no
sentinels, signature-is-the-product) without restating them. `-s` takes a
comma-separated list, e.g. `-s l-persona-design-architecture,l-style` — a
worker never sees the skill otherwise. Research/audit/test personas run
persona-only.

## Precondition

```bash
test "${HERDR_ENV:-}" = 1
```
Stop and tell the user if not running inside Herdr.

## Worker policy

Every worker is a **Hermes harness** (`--kind hermes`) — never `--kind
claude`/`codex`/`gemini`, they aren't installed/verified here. Model and
provider come from the task-planner's plan, per `l-spec-driven-development`'s
model-sizing rule: small/cheap for research, strong for design, spec,
implementation, and review.

**Never hardcode which provider is available — it differs per machine.**
Before planning, check what's actually usable right now:

```bash
hermes auth list          # OAuth/API-key providers with a live credential
```
`hermes auth list` shows only providers with a stored credential (e.g.
Anthropic via Claude subscription, GitHub Copilot via `gh auth token`, Nous
Portal via device-code OAuth) — a provider absent from that list is not
usable, full stop. Exclude `ollama-local`/any local model from
consideration on this machine even if it's registered in `providers:` —
this is a laptop, and running local inference competes with the laptop's
own battery/thermal budget instead of being genuinely free. Use it only if
the human explicitly asks for it in a given run.

Pick the cheapest reachable provider for research-tier work and the
strongest reachable one for design/spec/implementation/review — e.g. with
Nous Portal + Claude both authenticated, research goes to whichever is
cheaper per-token and build stages go to Claude; on a work box with only
GitHub Copilot, everything runs on Copilot since it's the only option.
State which provider got picked and why in the plan, don't assume the
last machine's setup still applies.

## Workflow

This is `l-spec-driven-development`'s autonomous mode: the human appears
at input, the spec gate, and each phase PR. Nowhere else.

1. Sync (`l-spec-driven-development`): fetch, base branch up to date with
   a clean tree. Spawn one task-planner worker
   (`-s l-persona-orchestrator-task-planner`), prompt it with the human's
   raw ask, `--wait`. It picks the governing spec and writes `PLAN.md`
   into the change's notes directory (`$SPEC_DIR` from here on): which
   personas run, how many, model/provider each, dependency order, and
   whether a phase needs parallel worktrees (see below).
2. Read `PLAN.md`, state it to the human in one or two lines, then execute
   it — spawn each worker the plan calls for, in the order/parallelism it
   specifies. Every worker's task prompt names `$SPEC_DIR` as where its
   output file goes, and the spec directory it amends.
3. Drive reconcile, research, design, review and spec autonomously, then
   open the spec PR and gate on it with `mcp__clarify`: the human merges
   it or gives feedback (run Feedback, gate again).
4. Phase loop: per `ROADMAP.md` phase, implement -> review -> test with no
   gate inside; relay a `FAIL` straight back to the programmer worker.
   Land the phase as its PR (trace block, run and revert lines), then
   gate with `mcp__clarify`: the human looks at the PR and its build, and
   merges or gives feedback. Merged -> sync the base, next phase.
   Feedback -> a fresh programmer worker runs Feedback on that PR, gate
   again.
5. Report COMPLETE after the last phase merged: requirement IDs built,
   every PR, every check as passed/failed/not run.

Parallel workers within one stage (e.g. market + technical research) each
write their own `$SPEC_DIR/<stage>-<persona-slug>.md`; before advancing to
the next stage, synthesize them into the canonical file
`l-spec-driven-development` expects (`RESEARCH.md`, `DESIGN.md`, ...).

## Parallel work in one repo: worktrees

Never point two concurrent workers at the same working tree. Each
concurrent implementer gets its own Herdr worktree; mechanics, landing
and cleanup are in `l-spec-driven-development` ("Parallel
implementation"). Research/design/review workers only write to
`$SPEC_DIR` and share the main checkout.

## Parallelism budget

Up to 3 independent, non-blocking things at once — worker panes,
subagents, or plain tool calls. Never start a 4th before one of the first
3 finishes; never parallelize a real dependency (e.g. design review needs
the design doc first).

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

# implementer/reviewer/designer workers additionally carry l-style:
herdr agent start programmer --kind hermes --pane <pane_id> --timeout 30000 \
  -- -m <model-from-plan> --provider <provider-from-plan> -s l-persona-programmer,l-style
```
`-m`/`--provider` after `--` set whichever model/provider the availability
check + plan assigned to this worker; `-s <persona-skill>[,l-style]` is
what makes the worker act as that role.

Verified: a bare `--kind hermes` start goes straight to `agent_status:
idle` — unlike native `claude`/`codex`/`gemini`, which show a one-time
workspace-trust dialog. If a start times out or comes back
`agent_not_ready` anyway:
```bash
herdr agent read <name> --source recent-unwrapped --lines 40
herdr agent get <name>
```

Name every worker for its role (`research-market`, `architect`,
`programmer`, `tester`, ...) — that's how you target prompts/reads and how
a human glancing at the Herdr sidebar reads the team.

## Driving a worker

```bash
herdr agent prompt research-market "<task, ending in: write findings to \$SPEC_DIR/RESEARCH-market.md, then stop>" --wait --timeout 120000
```
`--wait` blocks until the agent settles. Tell it to write its output to a
durable file under `$SPEC_DIR`, not pane text — every persona skill
already states this as its own output discipline. After it settles, read
the file directly:
```bash
cat "$SPEC_DIR/RESEARCH-market.md"
```

## Cleanup

```bash
herdr pane close <pane_id>
herdr worktree remove --workspace <id>   # per worktree, once its PR is open
```
Never close a pane or remove a worktree you did not create; never
`herdr server stop`.

## Pitfalls

- **A `cronjob` cannot do this skill's work** — no live Herdr session, so
  the precondition fails.
- **No persistence between chat sessions** — if the work needs to survive
  across sessions/polls, use `l-multi-agent-task-mode` or
  `l-single-agent-task-mode` instead.
- **Verified working**: hermes-kind panes spawn cleanly with no trust
  dialog, take a prompt via `agent prompt --wait`, and write their
  assigned file back to disk — the whole spawn -> prompt -> durable-file
  loop this skill relies on.
