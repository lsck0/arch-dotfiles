---
name: l-multi-agent-task-mode
description: "Self-poll a per-project taskwarrior db and spawn persona workers (Hermes panes under HERDR_ENV, else Claude Code Agent calls) to advance several +agent-task tickets in parallel through research, design, spec and phases (implement, review, test, land). Load when told to work a project's task queue with workers, to run an orchestrator pass over tasks/, or to decompose +prompt tickets. One ticket at a time without spawning: l-single-agent-task-mode; a live idea without a db: l-multi-agent-mode."
---

# Multi-agent task mode (self-polling orchestrator + persona workers)

This instance is an orchestrator driven by a per-project task db instead of a live human: it polls `+agent-task`
tickets, claims and advances them by spawning persona workers through a fixed pipeline (a worker per ticket, or per
stage within one ticket, inside the parallelism budget of `l-spec-driven-development`), and blocks on a human only
through documents (the spec PR and its `QUESTIONS.md`, or `tasks/context/questions/` plus tags), never by asking in
chat: nobody is guaranteed to watch a poll pass.

Load first, every time:

- `l-agent-task-db`: db layout, scaffolding, tag vocabulary, start/stop discipline, completion, the question-file
  shape. This skill only covers spawning and driving.
- `l-personas` and `l-spec-driven-development`: the same persona vocabulary and stage shape `l-multi-agent-mode`
  uses, so live and queue orchestration share them.
- [../l-multi-agent-mode/references/harness.md](../l-multi-agent-mode/references/harness.md): harness detection,
  worker policy, model choice, mechanics table, lifecycle. Task mode reads each worker's model from the ticket's
  `model:`/`provider:` annotation, never `fork`s a worker, writes outputs under `tasks/`, records workers as `worker:`
  annotations and reaps orphans at the start of every pass.
- [references/intake.md](references/intake.md): turning a `+prompt` into tickets, phase tickets after the spec
  merges, which workers a ticket gets, the stage-to-persona table.
- [references/pipeline.md](references/pipeline.md): a claimed ticket's directories, the stages per ticket kind, the
  fix loops and landing.

## Where it runs

Under a live Herdr session or Claude Code; never from a `cronjob` (no panes, no Agent tool). For unattended
progress, the backoff cron in `l-agent-task-db` runs `l-single-agent-task-mode` under the `orchestrator` Hermes
profile instead. Tickets carrying a `+stage-*` tag are owned by this skill: single mode skips them, including those
left `+human-clarification-needed` or `+human-review-ready`, so they resume on the next live pass of this skill. Live
Hermes sessions running this skill stay on the profile that launched them (usually `default`).

If the project has no `tasks/.taskrc`, scaffold one with `taskwarrior-init [project-dir]` instead of falling back
to a markdown queue; ask first only when it is genuinely unclear that a task db belongs in this project.

## Queue-poll procedure

1. Reap orphaned workers from an earlier pass (harness reference, Lifecycle). Then export state as JSON and parse it
   in code, never `task list` text:
   ```bash
   task '(+agent-task or +prompt)' status:pending export
   task +agent-task +READY export    # no open depends:, not waiting
   ```
2. Partition:
   - `+prompt` (not `+agent-task`): run Intake (`references/intake.md`) first; it takes priority over advancing
     decomposed tickets in the same pass.
   - Unclaimed (`+agent-task`, pending, `+READY`, no `+stage-*`, no `+human-*`): claim it in one beat with
     `task <id> start`, create `tasks/agents/<uuid8>-<slug>/`, annotate the workdir, add `+stage-queued`, then
     decide its workers (`references/intake.md`). No `model: ... provider: ...` annotation yet: run the single-ticket
     task-planner first (harness reference, model choice).
   - In progress (a `+stage-*`, no `+human-*`): `task <id> start` and reconstruct state from that stage's files under
     `tasks/context/` and `tasks/agents/<uuid8>-<slug>/`, not from conversation history.
   - Waiting on a PR (`+human-review-ready`): check the PR (Human gates); unchanged, skip and list it in the summary.
   - Blocked on clarification (`+human-clarification-needed`): without `+human-answered` skip and list it; with it,
     resume per Human gates.
   - Blocked by `depends:` (`+BLOCKED`): skip.
3. Work independent, non-blocking things at once (workers whose persona sets don't collide, or a worker beside an
   unrelated tool call) within the parallelism budget and 2-implementer cap. Never parallelize a real dependency
   chain (design review needs the design doc first).
4. The moment a ticket reaches a stopping point (question raised, stage advanced, PR opened, done), write the tag
   transition in the same tool call that changed the state, not batched at the end.
5. End the pass: close every worker still recorded, `task <id> stop` every ticket still started, and give a short
   summary: what advanced (with its new stage), what is now `+human-clarification-needed` or `+human-review-ready`
   and where its question file or PR is, what was marked done.

## Human gates

The autonomous gates of `l-spec-driven-development` become tags here. Their shared mechanics (start/stop, clearing
the block tag and `+human-answered` in one `task modify`, resuming) live in `l-agent-task-db`.

- **PR gate** (`+human-review-ready`). Two points stop for the human: the input (they file the `+prompt` or issue)
  and the spec PR from the `.spec` ticket. A phase PR waits on them only under `Merge policy: human` or when branch
  protection blocks the merge, and then they only merge, without reading code. Waiting on a PR: annotate
  `pr: <url>`, tag `+human-review-ready`, `task <id> stop`. Every pass checks each waiting PR itself (`gh pr view <n>
  --json state,updatedAt,reviews,comments`); the human never tags anything. Merged: clear the tag, `task <id> done`
  (the spec ticket first creates the phase tickets). New review or comment: run Feedback and wait again. Closed
  unmerged: `+human-clarification-needed` with the reason.
- **Clarification gate** (`+human-clarification-needed`), before the spec PR only: a decision only a human can make
  that materially changes the product, each with a recommendation, never trivia. Prefer the spec PR's
  `QUESTIONS.md`. Otherwise write `tasks/context/questions/<uuid8>-<slug>.md` (`l-agent-task-db`'s shape), tag it,
  annotate the path, `task <id> stop`; on resume fold the answer into `tasks/context/design/<uuid8>-*.md` and
  continue. After sign-off a spec gap that contradicts a signed-off requirement becomes a new spec PR on the phase
  ticket, waited on with the PR gate.

Either way move on to the next claimable ticket; never wait synchronously. If only the single-agent backoff cron
drives the queue, it does not resume this skill's tickets: say so plainly instead of implying the wake-up is
automatic.

## Pitfalls

- A `cronjob` cannot spawn workers; use the `l-single-agent-task-mode` cron there.
- Numeric ids are for immediate commands only; long-lived names use `<uuid8>-<slug>`, since taskwarrior renumbers
  pending ids when something completes.
- A ticket never carries two `+stage-*` tags, and a claimed ticket never has none.
- `tasks/agents/` and `tasks/context/` are durable state, not scratch. Ask whether the human wants `tasks/agents/`
  gitignored (pipeline-internal state often shouldn't ship in a PR); `tasks/context/` is normally tracked.
- Don't auto-commit in a repo whose convention forbids it (e.g. `l-dotfiles`): stop at a clean, reviewed working
  tree.
