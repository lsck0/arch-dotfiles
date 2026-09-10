---
name: l-single-agent-task-mode
description: "Poll a per-project taskwarrior/timewarrior db (scaffolding one via l-agent-task-db if missing) and work +agent-task tickets itself, ONE at a time claimed sequentially (though sub-actions within one ticket may run concurrently up to the shared parallelism budget), with NO Herdr spawning and no persona-worker pipeline. Same db/tracking mechanism as l-multi-agent-task-mode — the only difference is claiming one ticket at a time here vs. multiple there. Use for straightforward task-db-driven work that doesn't need a multi-role factory. For a live single idea in chat, use l-multi-agent-mode; to spawn Herdr persona workers per task, use l-multi-agent-task-mode."
---

# Single-agent task mode (self-polling, no spawning)

Both task-mode skills use the SAME `l-agent-task-db` mechanism — a
per-project taskwarrior/timewarrior db — for task tracking and planning.
The only difference between them is concurrency: this skill polls and
works exactly one ticket at a time, sequentially, itself; `l-multi-agent-task-mode`
polls the same db but can claim and work MULTIPLE tickets at once,
spawning a Herdr persona worker per ticket. This instance works a
project's taskwarrior queue directly, itself, one task at a time — no
Herdr, no worker panes, no persona pipeline. It reads a task, does the
work (research, writing, coding, whatever the task actually needs),
records the result durably, updates tags/priority, and moves to the next
task. This is the right mode when the work doesn't need multiple
specialist perspectives running in parallel — most routine queued work.

For db layout, scaffolding, tag vocabulary, and the `tasks/context/`
question-file convention, load `l-agent-task-db` first — hard
prerequisite, every time. For a live single idea worked directly in chat
with no task db, use `l-multi-agent-mode`. For task-db-driven work that
DOES warrant spawning Herdr persona workers (a real multi-stage pipeline:
research -> design -> implement -> review -> test, run by different
"roles"), use `l-multi-agent-task-mode` instead — that skill requires a
live Herdr session; this one does not.

## No Herdr precondition

Unlike the other two modes, this one has no `HERDR_ENV` requirement — it
runs in a plain Hermes session (including, unlike the other two modes,
inside a `cronjob` run, since it never spawns panes). This makes it the
natural body for the self-adjusting backoff poll cron described in
`l-agent-task-db` — set that cron's `prompt` to invoke this skill against
the project, and let the run's own progress/no-progress outcome drive the
reschedule at the end per that skill's procedure. That cron job should be
created under the `orchestrator` Hermes profile, not `default` — see
`l-agent-task-db`'s "The `orchestrator` Hermes profile" section for why
and how (its lighter context cap fits this mode's own habit of keeping
real state in `tasks/context/` rather than conversation history).

## Taskwarrior prerequisite

Load `l-agent-task-db` for detection/scaffolding. If the target project
has no `tasks/.taskrc` yet, scaffold one with that skill's
`scripts/scaffold.sh [project-dir]`. Only ask the user first if it's
genuinely ambiguous whether a task db belongs in this project at all.

## No stage tags

This mode has no worker-handoff pipeline, so the `+stage-*` vocabulary
from `l-agent-task-db` does not apply here — don't add stage tags to
tasks worked in this mode. Use plain taskwarrior state instead:
`pending` -> `task <id> start` (also starts timewarrior tracking) ->
work -> `task <id> done`, or `+human-clarification-needed` if genuinely
blocked.

## `+prompt` tasks

This mode has no Herdr precondition, so it cannot spawn the
`l-persona-orchestrator-task-planner` worker `l-multi-agent-task-mode`'s
intake procedure uses. If a poll pass finds an unclaimed `+prompt` task,
don't decompose it yourself — flag it in the end-of-pass summary and
leave it untouched for a live Herdr session running
`l-multi-agent-task-mode` to pick up.

## Working procedure

1. Export current state and parse in Python — never hand-parse `task
   list` text:
   ```bash
   task +agent-task export
   ```
   Also check for unclaimed `+prompt` tasks (`task +prompt export`) —
   report any in the end-of-pass summary per the "`+prompt` tasks"
   section above; don't touch them.
2. Partition:
   - **Blocked** — `+human-clarification-needed` present, no
     `+human-answered` yet: skip, note in the end-of-pass summary.
   - **Answered** — `+human-clarification-needed` + `+human-answered`
     both present: read the filled-in
     `tasks/context/questions/<id>-*.md`, fold the answer into the
     relevant `tasks/context/{research,design}/` doc, clear both tags in
     one `task modify` call, then treat it as workable this pass.
   - **Workable** — `+agent-task`, `status:pending`, no
     `+human-clarification-needed`.
3. Pick the single highest-priority workable task (taskwarrior's own
   `priority:` field, then `urgency` as tiebreaker — `task +agent-task
   +READY list` surfaces this ordering directly). Claim and work ONE
   ticket fully before claiming the next — never two tickets open at
   once in this mode (see step 5 for parallelism WITHIN one ticket,
   which is allowed).
4. `task <id> start` (begins timewarrior tracking via the hook).
5. Do the actual work yourself — no spawning. Read any existing
   `tasks/context/{research,design}/<id>-*.md` first so you're building on
   prior findings, not re-deriving from scratch. Independent sub-actions
   within this one task (e.g. two unrelated web lookups, or a lookup
   running alongside repo scaffolding) may run concurrently, up to the
   3-way parallelism budget in `l-agent-task-db` — the "one task at a
   time" rule below is about not claiming a second taskwarrior task in
   parallel, not about serializing every tool call within the task you're
   currently working. If a claimed task turns out to actually need a
   project-tree breakdown (multiple independent sub-workstreams,
   specialist handoffs) rather than being directly workable, that's out
   of scope here — flag it and hand off to `l-multi-agent-task-mode`'s
   intake procedure instead of forcing it through single-task work.
6. Write your findings/output to `tasks/context/research/<id>-<slug>.md`
   or `tasks/context/design/<id>-<slug>.md` as appropriate (or both) —
   this is the durable record, not just an annotation. Annotate the task
   with the file path(s):
   ```bash
   task <id> annotate "context: tasks/context/research/14-check-publications.md"
   ```
7. If you hit a decision only a human can make (materially changes the
   outcome, not trivia): write `tasks/context/questions/<id>-<slug>.md`
   per `l-agent-task-db`'s shape, `task <id> modify
   +human-clarification-needed`, `task <id> stop`, move to the next
   workable task — don't wait synchronously. If this project's queue is
   driven by the self-adjusting backoff poll cron (`l-agent-task-db`),
   the human answering and setting `+human-answered` is picked up
   automatically next pass with no manual re-trigger needed; otherwise
   say so rather than implying it wakes itself up.
8. If the task is genuinely complete: `task <id> stop`, then either `task
   <id> done` if this mode has clear authority to close it, or leave it
   `pending` with a completion note annotated and flag it in the summary
   for the human to close — match whatever the project's existing
   convention is; when unsure, prefer leaving it open with a clear
   annotation over silently marking done.
9. Re-adjust `priority:` on remaining tasks if this task's outcome changed
   what's now most urgent — priorities are a live signal, not set-once.
10. Move to the next workable task. Repeat until no workable tasks remain
    or a reasonable session budget is spent (don't run an unbounded loop
    in a single turn if the queue is very large — do a batch, summarize,
    and let the human decide whether to continue).
11. End with a short summary: what was completed, what's now
    `+human-clarification-needed` and where its question file is, what's
    left workable.
12. If this run was invoked by the self-adjusting backoff poll cron
    (`l-agent-task-db`): update `tasks/.poll-backoff` and
    `cronjob update` its own schedule per that skill's end-of-run rule —
    reset to 1 minute if anything advanced this pass, otherwise increment
    linearly. Skip this step entirely when running live in chat with no
    such cron wired up.

## Non-goals

- No Herdr panes, no persona skills, no multi-stage pipeline handoffs —
  if the task genuinely needs several different specialist perspectives
  in sequence with independent review, that's `l-multi-agent-task-mode`,
  not this one. If you find yourself wanting to spawn a second agent
  mid-task, stop and say so rather than working around the lack of one.
- Not for a single live idea with no task db — that's `l-multi-agent-mode`.

## Pitfalls

- **Use the task's UUID-derived identity / `id-slug`** for file names —
  taskwarrior renumbers pending ids once something completes/deletes.
- **`tasks/context/` is durable, shared project history** — write real
  findings there, not just a one-line annotation.
- Don't invent `+stage-*` tags here — that vocabulary belongs to
  `l-multi-agent-task-mode`'s worker-handoff tracking, not this
  sequential single-agent flow.
