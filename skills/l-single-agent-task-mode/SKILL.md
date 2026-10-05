---
name: l-single-agent-task-mode
description: "Poll a per-project taskwarrior db and work +agent-task tickets yourself, one at a time, no Herdr/worker spawning. Multi-role pipeline -> l-multi-agent-task-mode; live idea, no db -> l-multi-agent-mode."
---

# Single-agent task mode (self-polling, no spawning)

This instance works a project's `l-agent-task-db` (taskwarrior) queue
directly, itself, one task at a time: no Herdr, no worker panes, no
persona pipeline. It reads a task, does the work (research, writing,
coding, whatever the task actually needs), records the result durably,
updates tags/priority, and moves to the next task. The right mode when the
work doesn't need multiple specialist perspectives in parallel: most
routine queued work.

For db layout, scaffolding, tag vocabulary, completion, and the
`tasks/context/` question-file convention, load `l-agent-task-db` first:
hard prerequisite, every time. See the description for sibling routing
(multi-role pipeline vs. live-no-db); note the pipeline sibling
`l-multi-agent-task-mode` requires a live Herdr session, this one does not.

## No harness precondition

Unlike the other two modes, this one spawns no workers, so it needs neither
`HERDR_ENV` nor the Agent tool: it runs in a plain Hermes session (including,
unlike the other two modes, inside a `cronjob` run, since it never spawns
panes) or directly under Claude Code. This makes it the
natural body for the self-adjusting backoff poll cron described in
`l-agent-task-db`: set that cron's `prompt` to invoke this skill against
the project, and let the run's own progress/no-progress outcome drive the
reschedule at the end per that skill's procedure. That cron job should be
created under the `orchestrator` Hermes profile, not `default`: see
`l-agent-task-db`'s "The `orchestrator` Hermes profile" section for why
and how (its compression setting fits this mode's own habit of keeping
real state in `tasks/context/` rather than conversation history).

## Taskwarrior prerequisite

Load `l-agent-task-db` for detection/scaffolding. If the target project
has no `tasks/.taskrc` yet, scaffold one with `taskwarrior-init
[project-dir]`. Only ask the user first if it's genuinely ambiguous
whether a task db belongs in this project at all.

## No stage tags

This mode has no worker-handoff pipeline, so it never adds the `+stage-*`
vocabulary from `l-agent-task-db`. Use plain taskwarrior state instead:
`pending` -> `task <id> start` (also starts timewarrior tracking) ->
work -> `task <id> done`, or `+human-clarification-needed` /
`+human-review-ready` when waiting on the human.

A ticket that carries a `+stage-*` tag is claimed by
`l-multi-agent-task-mode`: skip it entirely, whatever its other tags, so
the two modes never both work one ticket.

## `+prompt` tasks

This mode has no Herdr precondition, so it cannot spawn the
`l-persona-orchestrator-task-planner` worker `l-multi-agent-task-mode`'s
intake procedure uses. If a poll pass finds an unclaimed `+prompt` task,
don't decompose it yourself: flag it in the end-of-pass summary and
leave it untouched for a live Herdr session running
`l-multi-agent-task-mode` to pick up.

## Spec-governed work

A ticket that changes code under a spec's `Implemented in` follows
`l-spec-driven-development`'s autonomous-mode gates: the change lands as
a PR with the spec updated in it, then annotate `pr: <url>`, tag
`+human-review-ready`, `task <id> stop`, and move on. Never merge or
self-approve. A ticket that needs a new spec plus several roadmap phases
is a project tree, not single-ticket work (step 5).

## Working procedure

1. Export current state and parse in Python; never hand-parse `task
   list` text:
   ```bash
   task +agent-task status:pending export
   task +agent-task +READY export    # the READY set: no open depends:, not waiting
   ```
   Also check for unclaimed `+prompt` tasks (`task +prompt status:pending
   export`): report any in the end-of-pass summary per the "`+prompt`
   tasks" section above; don't touch them.
2. Partition:
   - **Multi-mode owned**: any `+stage-*` tag. Skip, don't mention unless
     it looks stuck.
   - **Blocked**: `+human-clarification-needed` or `+human-review-ready`
     present, no `+human-answered` yet: skip, note in the end-of-pass
     summary.
   - **Answered question**: `+human-clarification-needed` +
     `+human-answered` both present: read the filled-in
     `tasks/context/questions/<uuid8>-*.md`, fold the answer into the
     relevant `tasks/context/{research,design}/` doc, clear both tags in
     one `task modify` call, then treat it as workable this pass.
   - **Answered PR**: `+human-review-ready` + `+human-answered` both
     present: check the annotated PR (`gh pr view <n> --json state`),
     clear both tags in one `task modify` call. Merged -> `task <id>
     done`. Open -> claim it, run `l-spec-driven-development`'s Feedback
     on the PR, gate again with `+human-review-ready`.
   - **Workable**: `+agent-task`, pending, `+READY`, no `+stage-*`, no
     `+human-clarification-needed`, no `+human-review-ready`.
3. Pick the single highest-priority workable task (taskwarrior's own
   `priority:` field, then `urgency` as tiebreaker; `task +agent-task
   +READY list` surfaces this ordering directly). Claim and work ONE
   ticket fully before claiming the next: never two tickets open at once
   in this mode (see step 5 for parallelism WITHIN one ticket, which is
   allowed).
4. `task <id> start` (begins timewarrior tracking via the hook).
5. Do the actual work yourself, no spawning. Read any existing
   `tasks/context/{research,design}/<uuid8>-*.md` first so you're building
   on prior findings, not re-deriving from scratch. Independent
   sub-actions within this one task (e.g. two unrelated web lookups, or a
   lookup running alongside repo scaffolding) may run concurrently, within
   the parallelism budget in `l-spec-driven-development` ("Parallelism and
   model choice"): the "one task at a time" rule is about not claiming a
   second taskwarrior task in parallel, not about serializing every tool
   call within the task you're currently working. If a claimed task turns
   out to actually need a project-tree breakdown (multiple independent
   sub-workstreams, specialist handoffs, a new spec with several phases)
   rather than being directly workable, that's out of scope here: `task <id>
   stop`, flag it and hand off to `l-multi-agent-task-mode`'s intake
   procedure instead of forcing it through single-task work.
6. Write your findings/output to `tasks/context/research/<uuid8>-<slug>.md`
   or `tasks/context/design/<uuid8>-<slug>.md` as appropriate (or both):
   this is the durable record, not just an annotation. uuid8 is the first
   8 chars of the task's uuid (`task _get <id>.uuid | cut -c1-8`).
   Annotate the task with the file path(s):
   ```bash
   task <id> annotate "context: tasks/context/research/3f2a9c1d-check-publications.md"
   ```
7. If you hit a decision only a human can make (materially changes the
   outcome, not trivia): write `tasks/context/questions/<uuid8>-<slug>.md`
   per `l-agent-task-db`'s shape, `task <id> modify
   +human-clarification-needed`, `task <id> stop`, move to the next
   workable task; don't wait synchronously. If this project's queue is
   driven by the self-adjusting backoff poll cron (`l-agent-task-db`),
   the human answering and setting `+human-answered` is picked up
   automatically next pass with no manual re-trigger needed; otherwise
   say so rather than implying it wakes itself up.
8. Finish per `l-agent-task-db` ("Completion: `task <id> done`"): `task
   <id> stop`, then `task <id> done` once the deliverable exists and is
   verified and its gate, if any, passed. A ticket that opened a PR
   stays pending at `+human-review-ready` until the human merged it.
9. Re-adjust `priority:` on remaining tasks if this task's outcome changed
   what's now most urgent: priorities are a live signal, not set-once.
10. Move to the next workable task. Repeat until no workable tasks remain
    or a reasonable session budget is spent (don't run an unbounded loop
    in a single turn if the queue is very large: do a batch, summarize,
    and let the human decide whether to continue).
11. End with a short summary: what was completed, what's now
    `+human-clarification-needed` or `+human-review-ready` and where its
    question file/PR is, what's left workable.
12. If this run was invoked by the self-adjusting backoff poll cron
    (`l-agent-task-db`): update `tasks/.poll-backoff` and
    `cronjob update` its own schedule per that skill's end-of-run rule:
    reset to 1 minute if anything advanced this pass, otherwise increment
    linearly. Skip this step entirely when running live in chat with no
    such cron wired up.

## Non-goals

- No Herdr panes, no persona skills, no multi-stage pipeline handoffs: if
  the task genuinely needs several different specialist perspectives in
  sequence with independent review, that's `l-multi-agent-task-mode`,
  not this one. If you find yourself wanting to spawn a second agent
  mid-task, stop and say so rather than working around the lack of one.
- Not for a single live idea with no task db: that's `l-multi-agent-mode`.

## Pitfalls

- **Numeric ids are for immediate commands only**: file names use
  `<uuid8>-<slug>`, since taskwarrior renumbers pending ids once something
  completes/deletes.
- **`tasks/context/` is durable, shared project history**: write real
  findings there, not just a one-line annotation.
- Don't add `+stage-*` tags here, and don't touch a ticket that has one:
  that vocabulary is `l-multi-agent-task-mode`'s claim marker.
