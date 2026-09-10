---
name: l-agent-task-db
description: "Shared taskwarrior+timewarrior conventions for l-multi-agent-task-mode and l-single-agent-task-mode: per-project tasks/ db layout, tasks/context/ folder, tag vocabulary for stage tracking and human-in-the-loop blocking. Load whenever operating in either task-mode skill, or asked to inspect/scaffold a project's agent task db directly."
---

# Agent task db conventions (shared mechanics)

This is a mechanics-only skill — it has no orchestration behavior of its
own. `l-multi-agent-task-mode` and `l-single-agent-task-mode` both load it
for: db layout, scaffolding, tag vocabulary, `tasks/context/` conventions,
and the human-question workflow. `l-multi-agent-mode` (pure live/direct
orchestration, no task db) does not use this skill at all.

## One db per project root

Each project root (a git repo, or a standalone non-repo folder like a
research initiative) gets its OWN isolated taskwarrior+timewarrior
instance — never a db shared across multiple unrelated projects:

```
<project-root>/
  tasks/
    .taskrc
    .task/              # data.location — gitignored, local state
    .timewarrior/        # gitignored, local state
    .poll-backoff         # gitignored, local state (self-adjusting poll cron)
    context/
      research/
      design/
      questions/
    agents/               # per-claimed-task pipeline-internal state (l-multi-agent-task-mode)
  devenv.nix              # enterShell exports TASKRC/TIMEWARRIORDB
  .envrc                   # `use devenv` — direnv auto-sources it on cd
```

If the project root also needs plain human-facing todos unrelated to
agent work, they live in the SAME db (see `+agent-task` below) — never
create a second parallel db for "the human's stuff" vs. "the agent's
stuff" in one project.

## Dashboard: exactly what's queued, what stage, what needs you

```bash
scripts/task-dashboard.py [project-dir]     # defaults to $PWD
```
Read-only, human-facing view (never modifies the db): `+prompt` tasks
still awaiting decomposition, tickets blocked on `+human-clarification-needed`
(with their question file path), tickets sitting at
`+human-review-ready` (spec approval gate), what's actively in progress,
what's ready/blocked, and recently completed tickets — each with its
`project:` family and `+stage-*`. Run this any time to see the whole
queue at a glance instead of hand-parsing `task list`/`task export`.

## Detecting / scaffolding

- Detect: `TASKRC` env var (auto-exported by devenv+direnv on shell
  entry), or a `<project-root>/tasks/.taskrc` file even when
  operating outside that shell (pass it explicitly:
  `TASKRC=./tasks/.taskrc task ...`).
- If neither exists, invoke the repository's `taskwarrior-init [project-dir]`
  command (defaults to `$PWD`). It delegates to this skill's
  `scripts/scaffold.sh` implementation and:
  - `git init`s a new repo at the target if it isn't already inside one
    (never touches an existing repo's history — an existing repo only
    gets its `.gitignore` extended), then writes `tasks/.taskrc` +
    `.task/` + `.timewarrior/`;
  - installs the `on-modify.timewarrior` hook so `task <id> start`/`stop`
    auto-tracks a matching timewarrior interval;
  - creates `tasks/context/{research,design,questions}/`;
  - creates a NEW `devenv.nix` + `.envrc` if none exists, OR — if
    `devenv.nix` already exists for the project's real dev tooling —
    PATCHES its `enterShell` block in place to add the
    `TASKRC`/`TIMEWARRIORDB` exports, leaving everything else in the file
    untouched (idempotent: re-running detects its own managed block and
    skips);
  - ensures `.gitignore` covers `tasks/.task/`, `tasks/.timewarrior/`,
    and `tasks/.poll-backoff` whenever a git repo is present (freshly
    created or pre-existing);
  - for a FRESH repo only, stages and commits exactly what it just wrote
    (`devenv.nix`, `.envrc`, `.gitignore`, `tasks/`) so the scaffold
    isn't left sitting uncommitted — never `git add -A`, so any
    unrelated pre-existing files in the target are left alone for the
    human to handle themselves.
  Auto-export-on-cd requires `eval "$(direnv hook zsh)"` in the shell rc
  (already wired in this repo's `configs/zsh/zshrc`) — without it,
  `devenv shell` still works, just not automatically on `cd`.
- Never scaffold a second db if one already exists at that root — the
  script itself refuses (`.taskrc` already exists), but check first
  regardless so you don't waste a call.

## Task lifecycle: start/stop discipline

`task <id> start` / `task <id> stop` aren't decorative — they drive the
`on-modify.timewarrior` hook, so they're the only source of truth for how
long a task was actually worked. Both task-mode skills follow this
without exception:

- The instant a task is claimed or resumed and real work begins,
  `task <id> start` — in the same beat as claiming it, not after.
- The instant work on it stops for this session — blocked on a human,
  handed to a worker that hasn't finished yet, or the poll pass is
  ending — `task <id> stop`. A task sitting `+human-clarification-needed`,
  `+human-review-ready`, or waiting for the next poll pass is PAUSED, not
  started; never leave it counted as "started" with no active work
  happening.
- Finishing (`+stage-complete` / `task <id> done`) should already be
  stopped from the step above — don't leave a dangling start or a
  double-stop.

## Parallelism budget: up to 3 concurrent, non-blocking

Both task-mode skills may run **up to 3 independent things at once** —
Herdr worker panes, subagents, or plain tool calls (e.g. a web lookup
running alongside repo scaffolding) — whenever those things genuinely
don't depend on each other's output. This is a ceiling, not a target: run
1 when only 1 thing is workable, run 2–3 when that many independent,
non-blocking things are actually ready at once. Never start a 4th
concurrent thing before one of the first 3 finishes, and never
parallelize things where one needs another's output first (e.g. a design
review needs the design doc to exist first) — that's a dependency chain
and stays sequential regardless of the budget.

## The `orchestrator` Hermes profile — where self-polling actually runs

A Hermes process's profile is fixed at launch — nothing a skill does
mid-session can switch it, and neither the `cronjob` MCP tool nor `herdr
agent start` take a profile argument; both operate against whichever
profile is already running them. So "the orchestrator uses a lighter
context cap" has to be solved by LAUNCHING the self-polling process under
the right profile, not by anything a skill instructs itself to do once
running.

This repo provisions that profile via `configs/hermes/link.sh`
(discovered by `install.sh`): a Hermes profile named `orchestrator`,
cloned from `default` (same model/provider/skills/`.env`), with
`compression.threshold_tokens: 100000` set ONLY in that profile's
`config.yaml` — appropriate because an orchestrator's real state lives in
`tasks/` (the taskwarrior db plus `tasks/context/`), not chat history, so
a small context window is enough. `default` (interactive chat) is never
touched.

**Any self-polling orchestrator process — a background loop, a spawned
worker, or the backoff poll cron below — should be launched under this
profile**, not `default`:
```bash
HERMES_HOME="${HOME}/.hermes/profiles/orchestrator" hermes cron create ...
# or, equivalently, using the profile's own alias:
orchestrator cron create ...
```
A LIVE session already running under `default` (e.g. a human talking to
Hermes directly in chat, invoking one of these skills interactively)
stays on `default` for that turn — there is no way to hop profiles
mid-conversation, and forcing one wouldn't be desirable anyway since a
live chat has a human present who benefits from full context. Reserve
`orchestrator` for processes that are themselves self-polling/unattended
(the case this whole section is about).

## Self-adjusting backoff poll cron (unattended queue polling)

When a project's queue relies on a `cronjob` nudge rather than a human
re-triggering a live pass, the poll cadence must self-adjust instead of
polling at a fixed rate forever or requiring the human to manually "wake"
it back up after answering a question:

- **State file**: `tasks/.poll-backoff` — a single integer, minutes
  since the last successful advance. Gitignored, local state, same as
  `tasks/.task/`.
- **Setup (once per project)**: create the poll job UNDER THE
  `orchestrator` PROFILE (see above) with `schedule="in 1m"` — use the
  `hermes cron create` CLI with `HERMES_HOME` set (or the `orchestrator`
  alias), not the `cronjob` MCP tool, since that tool is bound to
  whatever profile is running the CURRENT session (the one doing the
  setup, likely `default`). Then immediately edit it to bake its own
  returned job id into its prompt (a job doesn't otherwise know its own
  id), so every run can reschedule itself.
- **Inside each run**: once the job actually fires, the session executing
  it already belongs to the `orchestrator` profile (a job lives in
  whichever profile's cron store created it), so the `cronjob` MCP tool
  IS the right tool to reschedule itself at that point — no `HERMES_HOME`
  juggling needed from inside the run itself, only at initial setup time
  from a different (e.g. `default`) session.
- **End of every run**:
  - Progress happened this pass (claimed new work, cleared a
    `+human-clarification-needed`/`+human-review-ready` +
    `+human-answered` pair, a stage advanced) → write `1` to
    `.poll-backoff` and reschedule to `in 1m`.
  - No progress was possible (everything workable is
    `+human-clarification-needed` or `+human-review-ready` and still
    unanswered) → read current N from `.poll-backoff` (default 1),
    write `N+1`, and reschedule to `in {N+1}m`.
- Linear backoff, not exponential — 1, 2, 3, 4... minutes — so a
  long-blocked project still gets checked at a bounded, predictable rate.
  The human never has to manually kick the job after answering a
  question file; it comes back on its own within the current backoff
  window and snaps back to 1-minute checks the instant it finds progress
  again.

## `project:` = one decomposed prompt

Taskwarrior's own `project:` field is reused as "which prompt/initiative
does this ticket belong to" — not a separate sprint concept. One `+prompt`
task, once decomposed, becomes one `project:<slug>.*` family; every ticket
under it is one step from the task-planner's breakdown:

```bash
task add project:sale-tracker.research +agent-task "technical research"
task add project:sale-tracker.design +agent-task "architecture"
```

List/report by grouping the normal taskwarrior way:
```bash
task project:sale-tracker.research list
```

## Tag vocabulary

- `+prompt` — the human's raw ask, added by the human themselves
  (`task add +prompt "Investigate the 500s bug"`). This is intake, not
  work — it never carries `+agent-task` or a `+stage-*` tag, and no
  orchestrator picks it up to "work" in place. It exists to be
  decomposed: a task-planner worker turns it into a `project:<slug>.*`
  family of `+agent-task` tickets (see "Intake" in
  `l-multi-agent-task-mode`), and the `+prompt` task itself gets
  annotated with a pointer to that breakdown and closed — it was scope,
  not a unit of work. Keeping `+prompt` and `+agent-task` as two
  disjoint tags is deliberate: the human can add ordinary unrelated
  todos (plain taskwarrior usage, no tag at all, or `+prompt` for
  something not yet triaged) without them being swept into agent-managed
  scope by accident.
- `+agent-task` — opt-in marker. Only tasks carrying this tag are inside
  agent-managed scope; this lets the same db hold ordinary human todos
  (plain taskwarrior usage) alongside agent-run work without an agent
  sweeping up unrelated items. Set by a task-planner's decomposition
  pass on every ticket it creates, or added directly by the human when
  explicitly bringing an existing task into scope.
- Stage tags — **`l-multi-agent-task-mode` only**; `l-single-agent-task-mode`
  does not use these, it has no worker handoffs to track (see that
  skill). Exactly ONE active at a time:
  `+stage-queued +stage-research +stage-design +stage-design-review
  +stage-implement +stage-code-review +stage-test +stage-complete`
  Always remove the old one in the SAME `task modify` call that adds the
  new one — never let a task carry two:
  ```bash
  task 14 modify -stage-research +stage-design
  ```
- `+human-review-ready` — the ticket's spec (`SPEC.md`) is written and
  ready for the human review/approval gate
  (`l-spec-driven-development`'s step 5, the one human checkpoint in the
  pipeline). Co-exists with the ticket's current `+stage-*` tag so a
  resuming agent still knows where it is; cleared together with
  `+human-answered` once the human has reviewed (approved as-is, or
  edited `SPEC.md` directly) — see `+human-answered` below.
- `+human-clarification-needed` — the task is blocked on a decision only
  a human can make (a question written to
  `tasks/context/questions/<id>-*.md`). Co-exists with whatever other
  tags are active so the resuming agent knows where to pick back up.
- `+human-answered` — the universal "human has acted, resume me" signal,
  paired with whichever of the two tags above is active:
  - Clearing `+human-clarification-needed`: the human filled in the
    answer in the matching `tasks/context/questions/<id>-*.md` file and
    sets `+human-answered` THEMSELVES as an explicit "this is ready, go
    check it" signal — an agent does not infer readiness from non-empty
    file content alone; the tag is the trigger to even look. Once an
    agent has folded the answer back into the durable docs (e.g.
    `tasks/context/design/...`) and resumed the task, it clears BOTH
    `+human-clarification-needed` and `+human-answered` in the same
    `task modify` call — tags reflect current state only, the answer's
    own history lives in the doc (and git, once committed), not in a
    lingering tag.
  - Clearing `+human-review-ready`: the human has reviewed `SPEC.md`
    (approved as-is or edited it directly) and sets `+human-answered`
    themselves. Once an agent has picked the ticket back up (re-reading
    `SPEC.md` in case it changed) it clears BOTH `+human-review-ready`
    and `+human-answered` in the same `task modify` call, same
    discipline as above.

## Priorities

Taskwarrior's native `priority:` (H/M/L) is the live urgency signal — keep
it current as understanding of the task changes, don't set it once and
forget it. A task that just became `+human-clarification-needed`- or
`+human-review-ready`-blocked and sits on the critical path should
usually be bumped to H; routine follow-up work stays M/L.

## `tasks/context/` — durable docs, source of truth for everything

```
tasks/context/
  research/<id>-<slug>.md      # findings, spikes, investigation notes
  design/<id>-<slug>.md        # specs, decisions, architecture notes
  questions/<id>-<slug>.md     # open questions blocking a +human-clarification-needed task
```
Name files by the task's `id-slug` (see Pitfalls — the numeric id alone
is not durable). This directory is the durable record of WHY decisions
were made and WHAT was found — not agent conversation history, and not
taskwarrior annotations beyond a pointer to the file. Record the file's
path as a task annotation the moment it's created:
```bash
task 14 annotate "context: tasks/context/research/14-dark-mode-toggle.md"
```

### Question file shape

```markdown
# Task 14: Dark mode toggle
Stage: design
Asked: 2026-09-04

## Q1: Local accounts or OAuth?
This affects the API, data model, security model, and deployment
architecture.
Recommendation: OAuth.

**Your answer:**

```
One `## Q<n>` section per open decision, each with the same "why this
needs human judgment + a recommendation" framing a design-review gate
would use. Never ask trivial questions this way — if it doesn't
materially change the design, just decide it and record the reasoning in
`design/` instead of blocking on it.

## Pitfalls

- **Use the task's UUID-derived identity, not just its numeric id, for
  anything long-lived.** Taskwarrior renumbers pending task ids once
  something is completed/deleted; an `id-slug` file/dir name plus
  cross-checking the task's own annotation is what survives renumbering.
- **`tasks/.task/` and `tasks/.timewarrior/` are local state — gitignored.**
  `tasks/context/` is durable project history — track it in git normally
  unless the project has a specific reason not to.
- **Never let a task carry two `+stage-*` tags.**
- **Don't scaffold a second db** if `tasks/.taskrc` already exists at
  that root.
