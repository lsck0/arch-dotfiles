---
name: l-multi-agent-task-mode
description: "Self-poll a per-project taskwarrior db and spawn persona workers (Herdr/Hermes under HERDR_ENV, else Claude Code Agent tool) to advance multiple +agent-task tickets in parallel through a research->design->spec->phase (implement, review, test, land) pipeline. One ticket at a time, no spawning -> l-single-agent-task-mode; live idea, no db -> l-multi-agent-mode."
---

# Multi-agent task mode (self-polling orchestrator + persona workers)

This instance acts as an orchestrator that manages itself via a per-project
`l-agent-task-db` (taskwarrior/timewarrior) instead of live human
direction: it polls `+agent-task` tickets, claims and advances them by
spawning persona workers through a fixed pipeline (a worker per ticket, or
per pipeline stage within one ticket, within the parallelism budget in
`l-spec-driven-development`, "Parallelism and model choice"), and blocks on
a human only via `tasks/context/questions/` + tags, never via `clarify`
(the human isn't necessarily watching a poll pass). Workers are Hermes
panes under `HERDR_ENV=1`, else Claude Code Agent-tool calls (see
"Precondition: detect the harness").

This skill covers the SPAWNING/DRIVING half. For db layout, scaffolding,
tag vocabulary, completion, and the `tasks/context/` question-file
convention, load `l-agent-task-db` first: hard prerequisite, every time.
Load `l-personas` for persona discovery and `l-spec-driven-development`
for the stage shape, the parallelism budget and model-sizing rule
(small/cheap models for research, strong models for design, spec,
implementation and review): the same two skills `l-multi-agent-mode` loads, so live and queue
orchestration share one persona vocabulary and one stage shape. See the
description for sibling routing (single-ticket vs. live-no-db).

Worker harness policy: one harness per run, many roles. A worker is
differentiated only by its name, its prompt, and which **persona skill** it
carries, never by harness kind. Detect the harness once (see "Precondition"
below) and use that column of the mechanics table throughout:

- `HERDR_ENV=1`: every worker is a Hermes pane (`--kind hermes`), never
  `--kind claude`/`codex`/`gemini` (not installed/available here).
- Claude Code: every worker is an Agent tool call; a worker persona is an
  Agent prompt telling the worker to load the `l-persona-*` skill (plus the
  l-style parts below) before working.

Workers that design or write code (`l-persona-design-*`,
`l-persona-programmer`, `l-persona-reviewer`, `l-persona-tester`) carry the
`l-style` core plus `l-style-architecture`; a `l-persona-tester` worker adds
`l-style-testing`, a latex/math worker adds `l-style-latex`. Research and
audit personas run persona-only.

**Model choice is the task-planner's job, not this skill's.** Never
hardcode or independently re-derive which model/provider is available:
that's exactly the reachability check the `l-persona-orchestrator-task-planner`
worker already does during Intake (below) and bakes into each ticket's
`model:`/`provider:` annotation. This skill just reads that annotation
when spawning:
```bash
task <id> export   # the .annotations[] entry starting "model: <m> provider: <p>"
```
Under Claude Code the model is the Agent tool's `model` override and there
is no provider; the annotation's model still applies, provider is ignored.
Fallback ONLY for a ticket that reached this queue without going through
Intake (e.g. a human added `+agent-task` directly, skipping `+prompt`
decomposition): spawn one `l-persona-orchestrator-task-planner` worker
against that single ticket first (same as Intake step 1, scoped to one
ticket). It annotates the model/provider and, if the ticket has no
`project:`, assigns one. Don't decide the model yourself.

## Precondition: detect the harness

```bash
test "${HERDR_ENV:-}" = 1
```

- `HERDR_ENV=1`: a live Herdr session; workers are Hermes panes.
- Otherwise, running under Claude Code: workers are Agent tool calls,
  running concurrently in the background. There is no `HERDR_ENV`, no
  panes, no `herdr` CLI, so skip every `herdr` command and use the Claude
  Code column of the mechanics table.

Either way the taskwarrior db (a plain CLI) works the same. A `cronjob`
has neither a live Herdr session nor the Agent tool, so it cannot spawn
workers. The self-adjusting backoff poll cron in `l-agent-task-db` can
still keep a project moving unattended by invoking
`l-single-agent-task-mode` each tick instead: that mode spawns nothing,
runs under the `orchestrator` Hermes profile (`l-agent-task-db`'s
"The `orchestrator` Hermes profile" section), and works tickets this skill
hasn't claimed. Tickets carrying a `+stage-*` tag are owned by this skill;
single mode skips them, including ones this skill left
`+human-clarification-needed` or `+human-review-ready`, so those resume on
the next live pass of this skill. Live Hermes sessions running this skill
stay on whatever profile launched them (typically `default`), since those
panes are interactive/observed, not unattended.

## Taskwarrior prerequisite

Load `l-agent-task-db` for detection/scaffolding. If the target project
has no `tasks/.taskrc` yet, scaffold one with `taskwarrior-init
[project-dir]` rather than falling back to a parallel markdown queue.
Only ask the user first if it's genuinely ambiguous whether a task db
belongs in this project at all.

## Directory layout for a claimed task

```
<project-root>/
  tasks/                                        # see l-agent-task-db
    context/
      questions/3f2a9c1d-dark-mode-toggle.md    # shared across ALL tasks
      research/3f2a9c1d-dark-mode-toggle.md
      design/3f2a9c1d-dark-mode-toggle.md
    agents/
      3f2a9c1d-dark-mode-toggle/
        review/{design-review,code-review}.md
        implementation/report.md
        tests/report.md
```
Research/design findings go in `tasks/context/{research,design}/` (durable,
shared, human-readable project history per `l-agent-task-db`); review/
implementation/test artifacts that are pipeline-internal working state go
in `tasks/agents/<uuid8>-<slug>/`. uuid8 is the first 8 chars of the
task's uuid (`task _get <id>.uuid | cut -c1-8`); numeric ids are only for
immediate commands. Actual code changes for the implementer persona
happen in the REAL project tree at its real paths:
`implementation/report.md` records what changed and where, it is not a
copy of the code. Don't auto-commit: check for a skill governing this
repo's commit convention (e.g. `l-dotfiles`) same as any other edit.

## Dynamic persona discovery (do this before spawning anything)

Discover the current persona set via `l-personas`; never hand-maintain a
persona name list here, it will drift out of sync with what's actually
installed:
```python
personas = [s for s in skills_list()["skills"] if s["name"].startswith("l-persona-")]
```

## Deciding which workers to spawn (per task, dynamic)

Don't reflexively spawn every persona, and don't default to "always
research" or "never research." For each research persona, ask: **what
would research actually change about this task's design or
implementation?**

- `l-persona-research-codebase`: needed unless you can already point to
  the exact existing files/patterns/conventions this task touches. Most
  taskwarrior-queued tasks (existing-repo work) want this over external
  market/literature research: the unknowns are usually internal
  conventions, not external landscape.
- `l-persona-research-market` / `l-persona-research-literature`: needed
  only when there's a real open question with more than one plausible
  answer that changes the design shape.
- `l-persona-design-architecture` (research mode): needed for new
  components/data flow/failure modes; skip for a same-shape addition to
  an already-understood structure.
- A security-sensitive task (auth, payments, secrets, network-facing)
  adds `l-persona-auditor-security` at design review AND
  before/alongside testing regardless of other research.

Annotate the chosen worker set and the one-line research-included/skipped
reason onto the task itself (`task <id> annotate "..."`): there's no
guarantee a human is reading a live chat at poll time, so the log has to
live on the task.

## Intake: decomposing a `+prompt` into a project tree

A `+prompt` task (e.g. `task add +prompt "build a sale tracker for the
webshop gremlin gear"`) is the human's raw ask, not itself work to advance
through `+stage-*` tags: it's scope waiting to be broken down. Every
poll pass, check for unclaimed `+prompt` tasks first, before touching the
`+agent-task` queue:

1. Spawn one `l-persona-orchestrator-task-planner` worker (Herdr pane,
   `-s l-persona-orchestrator-task-planner`), prompt it with the
   `+prompt` task's description, `--wait`. This is the SAME persona
   `l-multi-agent-mode` uses for live decomposition: one breakdown brain
   for both live and queue-driven intake, including model/provider
   choice (see that persona's own reachability-check instructions). Tell
   it explicitly: this is queue mode, so its plan must translate into
   taskwarrior tickets, not just a `PLAN.md` narrative. It names the
   tickets in these groupings, skipping research or design when they
   don't apply (same research-necessity test as "Deciding which workers
   to spawn" above):
   - `project:<slug>.research`: one or more research tickets.
   - `project:<slug>.design`: depends on the research tickets.
   - `project:<slug>.spec`: exactly one ticket, depends on design; it
     writes `SPEC.md`/`ROADMAP.md`, opens the spec PR and gates with
     `+human-review-ready`.
   No separate testing tickets: testing runs inside each phase ticket.
   For every ticket it names the model/provider (small/cheap models for
   research, strong models for design, spec, implementation and review),
   plus one model/provider for the phase tickets to come.
2. From the plan, create the tickets:
   `task add project:<slug>.research +agent-task "technical research"`
   (repeat per ticket, per grouping). Every child gets `+agent-task`,
   since these are what future poll passes actually work. Wire
   `depends:` as above; independent research tickets stay
   dependency-free so they can run in parallel. Annotate each ticket with
   the model/provider the plan assigned it:
   `task <id> annotate "model: <model> provider: <provider>"`, and the
   `.spec` ticket also with the phase assignment:
   `task <id> annotate "phases: model: <model> provider: <provider>"`, so a
   later poll pass spawning this ticket's worker reads it directly
   instead of re-deriving it (see "Worker harness policy" above).
3. Write the plan itself to
   `tasks/context/design/<uuid8>-<slug>-intake.md` (uuid8 of the
   `+prompt` task) so the reasoning for the breakdown survives after the
   `+prompt` task closes.
4. Close the `+prompt` task immediately:
   `task <prompt-id> annotate "decomposed into project:<slug>.*: see tasks/context/design/<uuid8>-<slug>-intake.md"`
   then `task <prompt-id> done`. It was scope, not work; it never sits in
   the `+agent-task` queue itself.
5. Continue this same poll pass into the newly created tickets per the
   normal queue-poll procedure below: decomposition and the first
   claimable child(ren) can happen in the same pass.

**Phase tickets.** When the spec PR is merged, the agent creates one
phase ticket per `ROADMAP.md` phase:
`task add project:<slug>.p<k> +agent-task "p<k>: <what runs after it>"`,
each `depends:` on the previous phase ticket, each annotated
`model: <model> provider: <provider>` from the `.spec` ticket's
`phases:` annotation. If the `.spec` ticket carries none, run the
task-planner for the phase tickets first. Then `task <id> done` the
`.spec` ticket.

## Stages per ticket

Every claimed ticket carries exactly one `+stage-*` tag while claimed
(vocabulary in `l-agent-task-db`), starting at `+stage-queued`:

| ticket | stages | done when |
|---|---|---|
| `.research` | queued -> research | findings written and checked |
| `.design` | queued -> design -> design-review | design review passed |
| `.spec` | queued -> spec | spec PR merged, phase tickets created |
| `.p<k>` | queued -> implement -> code-review -> test -> land | phase PR merged |

`+stage-spec` covers writing `SPEC.md`/`ROADMAP.md` and opening the spec
PR. `+stage-land` covers landing per `l-spec-driven-development`'s Phase
loop and opening the phase PR. Completion follows `l-agent-task-db`
("Completion: `task <id> done`"): the agent marks the ticket done itself.

## Human gates (queue mode)

`l-spec-driven-development`'s autonomous gates are not `clarify` calls here
(no human is guaranteed to watch a poll pass). They become taskwarrior
tags whose shared mechanics (the start/stop discipline, clearing both the
block tag and `+human-answered` in one `task modify`, how resume works)
live in `l-agent-task-db` ("Task lifecycle", "Tag vocabulary",
"Completion"); this skill does not restate them. Two gate kinds:

- **PR gate** (`+human-review-ready`): three points stop for the human: (1)
  input, the human files the `+prompt`/issue; (2) the spec PR, opened by the
  `.spec` ticket; (3) each phase PR, opened by its `.p<k>` ticket. When a
  ticket opens a PR: annotate `pr: <url>`, tag `+human-review-ready`,
  `task <id> stop`. On resume (per `l-agent-task-db`): `gh pr view <n>
  --json state`; merged -> `task <id> done` (the spec ticket first creates
  the phase tickets); open -> run Feedback and gate again.
- **Clarification gate** (`+human-clarification-needed`): a mid-stage
  decision only a human can make, and only one that materially changes the
  product, each with a recommendation, never trivia. Write
  `tasks/context/questions/<uuid8>-<slug>.md` (`l-agent-task-db`'s shape),
  tag it, annotate the path, `task <id> stop`. On resume: fold the answer
  into `tasks/context/design/<uuid8>-*.md`, then continue.

Either way move on to the next claimable task, never wait synchronously. If
the queue is driven only by the `l-single-agent-task-mode` backoff cron
(`l-agent-task-db`), that cron skips stage-tagged tickets and does not
resume this skill's tickets: say so plainly rather than implying the wake-up
is automatic; they resume on the next live pass of this skill.

## Queue-poll procedure

1. Export current state as JSON and parse in Python; never hand-parse
   `task list` text:
   ```bash
   task '(+agent-task or +prompt)' status:pending export
   task +agent-task +READY export    # the READY set: no open depends:, not waiting
   ```
2. Partition the exported tasks:
   - **`+prompt`** (not `+agent-task`): run the "Intake" procedure above
     instead of the steps below; this always takes priority over
     advancing already-decomposed tickets in the same pass.
   - **Unclaimed**: `+agent-task`, pending, no `+stage-*` tag, no
     `+human-*` tag, `+READY`.
     Claim it: `task <id> start` in the same beat (see `l-agent-task-db`'s
     start/stop discipline), create its `tasks/agents/<uuid8>-<slug>/`
     tree, annotate the workdir, add `+stage-queued`, then proceed into
     whatever this task's scope warrants (see "Deciding which workers to
     spawn"). Check the ticket's annotations for a prior
     `"model: ... provider: ..."` before spawning its worker; if none
     exists (ticket wasn't created via Intake, e.g. a human-added ticket
     with no project), run the single-ticket task-planner fallback from
     "Worker harness policy" above first.
   - **In progress**: has a `+stage-*` tag, no `+human-*` tag. Resume
     that stage: `task <id> start`, read that stage's own artifact files
     (`tasks/context/` and/or `tasks/agents/<uuid8>-<slug>/`) to
     reconstruct state rather than re-deriving it from conversation
     history.
   - **Blocked on clarification / PR review**: `+human-clarification-needed`
     or `+human-review-ready` present. If `+human-answered` is not also set:
     skip, note it in the end-of-poll summary. If it is set: resume per the
     "Human gates" section above (its clear-both-tags and merged/open
     handling), which defers the shared mechanics to `l-agent-task-db`.
   - **Blocked by `depends:`** (`+BLOCKED`, not in the READY set): skip.
3. Work several independent, non-blocking things at once (separate workers
   whose persona sets don't collide, or a worker running alongside an
   unrelated plain tool call) within the parallelism budget and
   2-implementer cap in `l-spec-driven-development` ("Parallelism and model
   choice"). Never parallelize a genuine dependency chain (e.g. design
   review needs the design doc to exist first).
4. The instant a task reaches a stopping point (question raised, stage
   advanced, PR opened, done), write the tag transition immediately, in
   the same tool call that changed the state: not batched at the end.
5. End the pass with `task <id> stop` on every ticket still started and
   a short summary: what advanced (with new stage per task), what's now
   `+human-clarification-needed` or `+human-review-ready` and where its
   question file/PR is, what was marked done.

## Harness mechanics (one table, both harnesses)

Give every worker a meaningful unique name matching its role
(`research-market`, `research-codebase`, `design-architecture`,
`design-reviewer`, `implementer`, `reviewer`, `tester`, or a task-specific
name). The model comes from the ticket's `model:`/`provider:` annotation
(Intake), never redecided here. Tell every worker to write its output to a
durable file under `tasks/context/` or `tasks/agents/<uuid8>-<slug>/`, not
to pane/chat text; after it settles, read the file directly.

| operation | HERDR_ENV=1 (Hermes panes) | Claude Code (Agent tool) |
|---|---|---|
| spawn a worker | `herdr pane split --current --direction right --cwd "$PROJECT_DIR" --no-focus` (read `.result.pane.pane_id`), then `herdr agent start <name> --kind hermes --pane <id> --timeout 30000 -- -m <model> --provider <prov> -s <persona>[,l-style,l-style-architecture[,l-style-testing]]` | one Agent tool call per worker (`subagent_type` general-purpose); set `model` to the annotation's model; the prompt names the role, tells the worker to load the `l-persona-*` skill (and the l-style parts) and to write its output to the durable file then stop |
| isolate parallel edits | `herdr worktree create`; the worker starts in the worktree root pane and skips the split | pass `isolation: "worktree"` on the Agent call |
| drive / follow up | `herdr agent prompt <name> "<task, ending in: write to <file>, then stop>" --wait --timeout 120000` | `SendMessage` to the worker's id/name with its context intact |
| wait for completion | `--wait` blocks until settled; else `herdr agent get <name>` until idle | no polling: background agents run concurrently, completion notifications arrive automatically |
| read a worker's result | `cat "$PROJECT_DIR/tasks/context/research/<uuid8>-<slug>.md"` | same `cat` of the durable file |
| cleanup | `herdr pane close <pane_id>`; `herdr worktree remove --workspace <id>` once its PR is open | nothing to close; a `worktree` isolation is auto-cleaned when unchanged |

`-s <persona-skill>[,l-style,...]` (Hermes) or the load-these-skills
instruction in the Agent prompt (Claude Code) is what makes a worker behave
as that role; pick the persona from the discovery step.

Herdr notes: a bare `--kind hermes` start goes straight to `agent_status:
idle`, unlike native CLIs that show a one-time trust dialog. If a start
times out or returns `agent_not_ready`, inspect with `herdr agent read
<name> --source recent-unwrapped --lines 40` and `herdr agent get <name>`.

## Pipeline stages -> persona mapping

| stage | persona skill | worker name |
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

Cross-check this table against `l-personas`' own list before spawning: it
drifts as personas are added/renamed; that skill's dynamic discovery
snippet is the source of truth, this table is just a pipeline-stage
convenience mapping over it.

Run every spawned research worker in parallel (Hermes: spawn all panes,
prompt all, then poll each with `herdr agent get <name>` until idle; Claude
Code: issue all Agent calls in one turn and await their completion
notifications) before moving to synthesis.

## Fix loop

Per phase ticket, before IMPLEMENT: fetch, base branch up to date with a
clean tree (the previous phase merged), then branch
`<type>/spec-<nnn>-p<k>-<slug>` (`l-spec-driven-development`, Phase
loop). Two tickets implemented at once each get their own isolated
worktree (`l-spec-driven-development`, "Parallel implementation"; the
mechanics table's isolate row), within its 2-implementer cap, and
`tasks/context/` stays in the main checkout.

```
design ticket:  DESIGN -> DESIGN-REVIEW
  DESIGN-REVIEW FAIL -> designer gets review/design-review.md -> DESIGN -> DESIGN-REVIEW
  DESIGN-REVIEW PASS -> done
phase ticket:   IMPLEMENT -> REVIEW -> TEST -> LAND
  REVIEW FAIL -> implementer gets review/code-review.md -> IMPLEMENT -> REVIEW
  TEST FAIL   -> implementer gets tests/report.md -> IMPLEMENT -> REVIEW -> TEST
  TEST PASS   -> LAND -> phase PR, +human-review-ready
```
Stage tags follow the loop (`+stage-implement`, `+stage-code-review`,
`+stage-test`, `+stage-land`; `+stage-design`, `+stage-design-review`),
swapped in one `task modify` each time. No human gate inside this loop.
LAND per `l-spec-driven-development`'s Phase loop: spec updated in the
same PR, trace block, run and revert lines, then switch back to the base
with a clean tree. The phase PR is a human gate (`+human-review-ready`,
above): open it and stop; the human merges or gives feedback. Don't
merge or self-approve. A repo whose convention forbids auto-committing
(e.g. `l-dotfiles`) -> stop at a clean, reviewed working tree and leave
the commit to the human, same deference as the "Don't auto-commit" rule
above. The ticket is `task <id> done` once its PR is merged (see
`l-agent-task-db`, "Completion").

Cleanup is the mechanics table's last row. Under Herdr, never close a pane
or remove a worktree you did not create, and never `herdr server stop`.

## Pitfalls

- **A `cronjob` cannot spawn workers**: it has neither `HERDR_ENV` nor the
  Agent tool, so neither harness column applies; use the
  `l-single-agent-task-mode` cron instead.
- **Numeric ids are for immediate commands only**: long-lived file/dir
  names use `<uuid8>-<slug>`, since taskwarrior renumbers pending ids once
  something completes/deletes.
- **Never let a task carry two `+stage-*` tags**, and never leave a
  claimed ticket with none.
- **`tasks/agents/` and `tasks/context/` hold durable state, not throwaway
  scratch**: check whether the human wants `tasks/agents/` gitignored
  (pipeline-internal working state often shouldn't ship in a PR);
  `l-agent-task-db` already establishes `tasks/context/` should normally
  be tracked.
