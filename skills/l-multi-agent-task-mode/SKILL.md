---
name: l-multi-agent-task-mode
description: "Turn this running instance into an orchestrator that self-polls a per-project taskwarrior/timewarrior db (scaffolding one via l-agent-task-db if missing) and spawns Herdr persona workers to advance MULTIPLE +agent-task tickets in parallel through a fixed pipeline. Same db/tracking mechanism as l-single-agent-task-mode — the only difference is claiming/working several tickets at once here vs. one there. Blocks on human input via tasks/context/questions/ + tags, not live chat. For a single live idea with no task db, use l-multi-agent-mode instead; for polling one ticket at a time WITHOUT spawning workers, use l-single-agent-task-mode."
---

# Multi-agent task mode (self-polling orchestrator + Herdr workers)

Both task-mode skills use the SAME `l-agent-task-db` mechanism — a
per-project taskwarrior/timewarrior db — for task tracking and planning.
The only difference between them is concurrency: `l-single-agent-task-mode`
polls and works exactly one ticket at a time, sequentially, itself; this
skill polls the same db but can claim and work MULTIPLE tickets at once,
spawning a Herdr persona worker per ticket (or per pipeline stage within
one ticket), up to the shared 3-way parallelism budget. Hermes acts as an
orchestrator that manages itself via that db instead of live human
direction: it polls `+agent-task` tickets, claims and advances them by
spawning Herdr persona workers through a fixed pipeline, and blocks on a
human only via `tasks/context/questions/` + tags — never via
`mcp__clarify` (the human isn't necessarily watching a poll pass).

This skill covers the SPAWNING/DRIVING half. For db layout, scaffolding,
tag vocabulary, and the `tasks/context/` question-file convention, load
`l-agent-task-db` — it is a hard prerequisite, load it first every time.
Load `l-personas` for persona discovery and `l-spec-driven-development`
for the stage shape and model-sizing rule (small/cheap for research,
strong for design/spec/implementation/review) — same two skills
`l-multi-agent-mode` loads, so live and queue orchestration share one
persona vocabulary and one stage shape instead of drifting apart. For a
single live idea worked directly in chat with no task db at all, use
`l-multi-agent-mode` instead. For task-db polling that works tasks
itself WITHOUT spawning workers, use `l-single-agent-task-mode`.

Worker harness policy (hard requirement): every worker is a **Hermes
harness** (`--kind hermes`). Never spawn `--kind claude`, `codex`,
`gemini`, or any other native CLI — they are not installed/available on
this machine. One harness, many roles: every worker is differentiated
only by pane name, prompt, and which **persona skill** it's preloaded
with — never by harness kind.

**Model/provider choice is the task-planner's job, not this skill's.**
Never hardcode or independently re-derive which provider is available —
that's exactly the reachability check the `l-persona-orchestrator-task-planner`
worker already does during Intake (below) and bakes into each ticket's
`model:`/`provider:` annotation. This skill just reads that annotation
when spawning:
```bash
task <id> export   # inspect .annotations[] for "model: <m> provider: <p>"
```
Fallback ONLY for a ticket that reached this queue without going through
Intake (e.g. a human added `+agent-task` directly, skipping `+prompt`
decomposition) — in that case, spawn one `l-persona-orchestrator-task-planner`
worker against that single ticket first (same as Intake step 1, scoped to
one ticket) rather than deciding the model yourself; don't run
`hermes auth list` from this skill directly.

## Precondition

```bash
test "${HERDR_ENV:-}" = 1
```
Stop and tell the user if not running inside Herdr — spawning/driving
Herdr panes only works live inside a real Herdr session. A `cronjob`
cannot run this skill's spawning/driving work directly (no `HERDR_ENV`),
but the self-adjusting backoff poll cron in `l-agent-task-db` can still
keep a project moving unattended by invoking `l-single-agent-task-mode`
each tick instead — that mode has no Herdr requirement, runs under the
`orchestrator` Hermes profile (`l-agent-task-db`'s "The `orchestrator`
Hermes profile" section), and can claim/work non-multi-persona tasks
itself, including resuming anything this skill left
`+human-clarification-needed` once a human answers. Reserve live Herdr
sessions running this skill
specifically for tasks that actually need the multi-persona pipeline —
those still run under whatever profile launched the live session
(typically `default`), since Herdr panes are interactive/observed, not
unattended.

## Taskwarrior prerequisite

Load `l-agent-task-db` for detection/scaffolding. If the target project
has no `tasks/.taskrc` yet, scaffold one with that skill's
`scripts/scaffold.sh [project-dir]` rather than falling back to a
parallel markdown queue. Only ask the user first if it's genuinely
ambiguous whether a task db belongs in this project at all.

## Directory layout for a claimed task

```
<project-root>/
  tasks/                                 # see l-agent-task-db
    context/
      questions/14-dark-mode-toggle.md    # shared across ALL tasks
      research/14-dark-mode-toggle.md
      design/14-dark-mode-toggle.md
    agents/
      14-dark-mode-toggle/
        review/{design-review,code-review}.md
        implementation/report.md
        tests/report.md
```
Research/design findings go in `tasks/context/{research,design}/` (durable,
shared, human-readable project history per `l-agent-task-db`); review/
implementation/test artifacts that are pipeline-internal working state go
in `tasks/agents/<id-slug>/`. Use the task's `id-slug` (see Pitfalls on
why the numeric id alone isn't durable). Actual code changes for the
implementer persona happen in the REAL project tree at its real paths —
`implementation/report.md` records what changed and where, it is not a
copy of the code. Don't auto-commit — check for a skill governing this
repo's commit convention (e.g. `l-dotfiles`) same as any other edit.

## Dynamic persona discovery (do this before spawning anything)

Discover the current persona set via `l-personas` — never hand-maintain
a persona name list here, it will drift out of sync with what's actually
installed:
```python
personas = [s for s in skills_list()["skills"] if s["name"].startswith("l-persona-")]
```

## Deciding which workers to spawn (per task, dynamic)

Don't reflexively spawn every persona, and don't default to "always
research" or "never research." For each research persona, ask: **what
would research actually change about this task's design or
implementation?**

- `l-persona-research-codebase` — needed unless you can already point to
  the exact existing files/patterns/conventions this task touches. Most
  taskwarrior-queued tasks (existing-repo work) want this over external
  market/literature research — the unknowns are usually internal
  conventions, not external landscape.
- `l-persona-research-market` / `l-persona-research-literature` — needed
  only when there's a real open question with more than one plausible
  answer that changes the design shape.
- `l-persona-design-architecture` (research mode) — needed for new
  components/data flow/failure modes; skip for a same-shape addition to
  an already-understood structure.
- A security-sensitive task (auth, payments, secrets, network-facing)
  adds `l-persona-auditor-security` at design review AND
  before/alongside testing regardless of other research.

Annotate the chosen worker set and the one-line research-included/skipped
reason onto the task itself (`task <id> annotate "..."`) — there's no
guarantee a human is reading a live chat at poll time, so the log has to
live on the task.

## Intake: decomposing a `+prompt` into a project tree

A `+prompt` task (e.g. `task add +prompt "build a sale tracker for the
webshop gremlin gear"`) is the human's raw ask, not itself work to advance
through `+stage-*` tags — it's scope waiting to be broken down. Every
poll pass, check for unclaimed `+prompt` tasks first, before touching the
`+agent-task` queue:

1. Spawn one `l-persona-orchestrator-task-planner` worker (Herdr pane,
   `-s l-persona-orchestrator-task-planner`), prompt it with the
   `+prompt` task's description, `--wait`. This is the SAME persona
   `l-multi-agent-mode` uses for live decomposition — one breakdown brain
   for both live and queue-driven intake, including model/provider
   choice (see that persona's own reachability-check instructions). Tell
   it explicitly: this is queue mode, so its plan must translate into
   taskwarrior tickets, not just a `PLAN.md` narrative — name the
   `project:<slug>.*` groupings (research/design/implementation/testing,
   skipping any that don't apply — same research-necessity test as
   "Deciding which workers to spawn" above), the tickets within each,
   the `depends:` ordering between them, AND which model/provider each
   ticket gets (small/cheap for research, strong for
   design/spec/implementation/review — `l-spec-driven-development`'s
   model-sizing rule).
2. From the plan, create the tickets:
   `task add project:<slug>.research +agent-task "technical research"`
   (repeat per ticket, per grouping) — every child gets `+agent-task`
   too, since these are what future poll passes actually work. Wire
   `depends:` so downstream groupings can't be claimed before their
   prerequisites (design depends on research, implementation depends on
   design review, testing depends on implementation); independent
   tickets within one grouping stay dependency-free so they can run
   within the parallelism budget (`l-agent-task-db`). Annotate each
   ticket with the model/provider the plan assigned it —
   `task <id> annotate "model: <model> provider: <provider>"` — so a
   later poll pass spawning this ticket's worker reads it directly
   instead of re-deriving it (see "Worker harness policy" above).
3. Write the plan itself to
   `tasks/context/design/<prompt-id>-<slug>-intake.md` so the reasoning
   for the breakdown survives even after the `+prompt` task closes.
4. Close the `+prompt` task immediately —
   `task <prompt-id> annotate "decomposed into project:<slug>.* — see tasks/context/design/<prompt-id>-<slug>-intake.md"`
   then `task <prompt-id> done`. It was scope, not work; it never sits in
   the `+agent-task` queue itself.
5. Continue this same poll pass into the newly created tickets per the
   normal queue-poll procedure below — decomposition and the first
   claimable child(ren) can happen in the same pass.

This replaces the flat model of one task carrying `+stage-*` through its
own lifecycle for anything bigger than a single well-scoped unit of work
— `+stage-*` still applies to each CHILD task's own advancement through
research -> design -> implement -> review -> test where that child itself
needs multiple specialist handoffs; a small child task (e.g. "market
research") may just go pending -> start -> done without ever touching
stage tags, same as `l-single-agent-task-mode`'s convention, when one
worker persona covers its entire scope in one shot.

## The one human gate, queue-mode version

`l-spec-driven-development`'s one real human gate (step 5, spec review)
becomes `+human-review-ready` here: once a ticket's `SPEC.md` is written,
tag it `+human-review-ready` and stop advancing that ticket's stage until
the human clears it (see "Blocking on a human question" below — same
mechanics, different tag). Judgment-call decisions that come up mid-stage
(not the spec-review gate itself) still go through
`tasks/context/questions/` + `+human-clarification-needed` — same content
bar as a design-review gate would use (only calls that materially change
the product, never trivia, each with a recommendation).

## Queue-poll procedure

1. Export current state as JSON and parse in Python — never hand-parse
   `task list` text:
   ```bash
   task '(+agent-task or +prompt)' export
   ```
2. Partition the exported tasks:
   - **`+prompt`, unclaimed** — run the "Intake" procedure above instead
     of the steps below; this always takes priority over advancing
     already-decomposed tickets in the same pass.
   - **Unclaimed, already decomposed** — `+agent-task`, `status:pending`,
     no `+stage-*` tag, part of an existing `project:<slug>.*` tree.
     Claim it: `task <id> start` in the same beat (see `l-agent-task-db`'s
     start/stop discipline), create its `tasks/agents/<id>-<slug>/` tree,
     annotate the workdir, add `+stage-queued`, then proceed into
     whatever this task's scope warrants (see "Deciding which workers to
     spawn"). Check the ticket's annotations for a prior
     `"model: ... provider: ..."` from Intake before spawning its worker
     — if none exists (ticket wasn't created via Intake), run the
     single-ticket task-planner fallback from "Worker harness policy"
     above first.
   - **In progress, not blocked** — has a `+stage-*` tag, no
     `+human-clarification-needed`/`+human-review-ready`. Resume that
     stage: read that stage's own artifact files (`tasks/context/`
     and/or `tasks/agents/<id>/`) to reconstruct state rather than
     re-deriving it from conversation history.
   - **Blocked on clarification** — `+human-clarification-needed`
     present. Check whether the human has added `+human-answered` (see
     `l-agent-task-db`). If yes: read the filled-in
     `tasks/context/questions/<id>-*.md`, fold the answers into
     `tasks/context/design/<id>-*.md`, clear both
     `+human-clarification-needed` and `+human-answered` in one `task
     modify` call, `task <id> start`, resume. If not yet answered: skip
     it, note it in the end-of-poll summary, move to the next claimable
     task.
   - **Blocked on spec review** — `+human-review-ready` present. Check
     whether the human has added `+human-answered`. If yes: re-read
     `SPEC.md` (the human may have edited it directly), clear both
     `+human-review-ready` and `+human-answered` in one `task modify`
     call, `task <id> start`, advance to the roadmap/implementation
     stage. If not yet answered: skip it, note it in the end-of-poll
     summary, move to the next claimable task.
3. Work up to 3 independent, non-blocking things at once — separate
   Herdr panes/tasks whose persona sets don't collide, or a worker pane
   running alongside an unrelated plain tool call — per the parallelism
   budget in `l-agent-task-db`. Never exceed 3 concurrent, and never
   parallelize a genuine dependency chain (e.g. design review needs the
   design doc to exist first).
4. The instant a task reaches a stopping point (question raised, stage
   complete, or `+stage-complete`), write the tag transition immediately,
   in the same tool call that changed the state — not batched at the end.
5. End the pass with a short summary: what advanced (with new stage per
   task), what's now `+human-clarification-needed` or
   `+human-review-ready` and where its question file/spec is, what hit
   `+stage-complete`.

## Blocking on a human question (queue mode)

When a stage needs a decision only a human can make and this is a poll
pass (no live chat turn right now), do NOT call `clarify`. Instead:

1. Write `tasks/context/questions/<id>-<slug>.md` per `l-agent-task-db`'s
   shape.
2. `task <id> modify +human-clarification-needed`, annotate with the file
   path, then `task <id> stop` — it's paused, not actively worked, until
   answered (see `l-agent-task-db`'s start/stop discipline).
3. Move on to the next claimable task — never wait synchronously for an
   answer in queue mode.

The human answers in the file and sets `+human-answered` themselves.
Getting picked back up is automatic if this project's queue is driven by
the self-adjusting backoff poll cron (`l-agent-task-db`) — the human
never has to manually re-trigger anything; the next poll (within the
current backoff window, capped at linear growth) detects
`+human-answered`, resumes and `task <id> start`s the task, and the
backoff itself snaps back to 1 minute since progress was made. If this
project isn't cron-driven yet and relies on the human re-invoking this
skill live instead, say so plainly — don't imply the wake-up is automatic
when it isn't.

The spec-review gate (`+human-review-ready`) follows the identical
mechanic — `task <id> modify +human-review-ready`, `task <id> stop`, the
human reviews/edits `SPEC.md` and sets `+human-answered` themselves, the
next poll resumes it — just no question file, since the artifact under
review is `SPEC.md` itself, not a `## Q<n>` list.

## Spawning a worker pane (mechanics, verified working)

```bash
herdr pane split --current --direction right --cwd "$PROJECT_DIR" --no-focus
# -> read new pane id from .result.pane.pane_id

herdr agent start research-market --kind hermes --pane <pane_id> --timeout 30000 \
  -- -m <model-from-annotation> --provider <provider-from-annotation> -s l-persona-research-market

# implementer/reviewer workers additionally carry l-style:
herdr agent start implementer --kind hermes --pane <pane_id> --timeout 30000 \
  -- -m <model-from-annotation> --provider <provider-from-annotation> -s l-persona-programmer,l-style
```
`-m`/`--provider` after `--` pin whichever model/provider the
task-planner assigned this ticket (its `"model: ... provider: ..."`
annotation from Intake) — never redecided here. `-s <persona-skill>[,l-style]`
is what makes this worker behave as that role — pick the persona from
the discovery step.

Verified behavior: a bare `--kind hermes` start went straight to
`agent_status: idle` on first run — unlike native `claude`/`codex`/
`gemini` CLIs, which show a one-time workspace-trust dialog. If a start
ever times out or comes back `agent_not_ready` anyway:
```bash
herdr agent read research-market --source recent-unwrapped --lines 40
herdr agent get research-market
```

Give every worker a meaningful unique name matching its role
(`research-market`, `research-codebase`, `design-architecture`,
`design-reviewer`, `implementer`, `reviewer`, `tester`, or a
task-specific name for a persona spawned ad hoc).

## Driving a worker

```bash
herdr agent prompt research-market "<task, ending in: write findings to tasks/context/research/14-dark-mode-toggle.md, then stop>" --wait --timeout 120000
```
`--wait` blocks until the agent settles. Tell the worker to write its
output to a durable file rather than trusting captured pane text. After
it settles, verify the artifact exists and read it directly:
```bash
cat "$PROJECT_DIR/tasks/context/research/14-dark-mode-toggle.md"
```

## Pipeline stages -> persona mapping

| stage | persona skill | pane name |
|---|---|---|
| market research | `l-persona-research-market` | research-market |
| literature/technical research | `l-persona-research-literature` | research-literature |
| architecture research/design | `l-persona-design-architecture` | design-architecture |
| codebase research | `l-persona-research-codebase` | research-codebase |
| synthesis | none (this instance, or `l-persona-design-architecture`) | synthesis |
| API design | `l-persona-design-api` | design-api |
| UI/UX design | `l-persona-design-uiux` | design-uiux |
| design review | `l-persona-design-architecture` + optionally `l-persona-auditor-security` | design-reviewer(-sec) |
| implementer | `l-persona-programmer` | implementer |
| code reviewer | `l-persona-reviewer` | reviewer |
| tester | `l-persona-tester` | tester |

Cross-check this table against `l-personas`' own list before spawning —
it drifts as personas are added/renamed; that skill's dynamic discovery
snippet is the source of truth, this table is just a pipeline-stage
convenience mapping over it.

Run every spawned research worker in parallel (spawn all panes first,
prompt all, then poll each with `herdr agent get <name>` until idle)
before moving to synthesis.

## Fix loop

```
IMPLEMENT -> REVIEW -> TEST
  TEST fail -> prompt implementer with tests/report.md contents -> IMPLEMENT again -> TEST
  TEST pass -> COMPLETE
```
No human gate inside this loop — the one human gate
(`+human-review-ready`) already happened earlier, at spec approval,
before the roadmap/implementation stage began. On `+stage-complete`, set
that tag on the task — don't run `task <id> done` automatically;
completing the taskwarrior task itself is the human's call, since "the
pipeline finished a pass" and "I'm satisfied with the result" aren't
always the same thing.

## Cleanup

Close panes once a stage's worker is no longer needed for live
monitoring:
```bash
herdr pane close <pane_id>
```
Never close a pane you did not create, and never `herdr server stop`.

## Pitfalls

- **A `cronjob` cannot spawn/drive Herdr panes** — `HERDR_ENV` won't be
  set in a cron job's fresh session, so the precondition fails.
- **Use the task's UUID-derived identity / `id-slug`, not just its
  numeric id**, for anything long-lived — taskwarrior renumbers pending
  ids once something completes/deletes.
- **Never let a task carry two `+stage-*` tags.**
- **`tasks/agents/` and `tasks/context/` hold durable state, not throwaway
  scratch** — check whether the human wants `tasks/agents/` gitignored
  (pipeline-internal working state often shouldn't ship in a PR); `l-agent-task-db`
  already establishes `tasks/context/` should normally be tracked.
