# Intake and worker choice

Part of `l-multi-agent-task-mode`: how a `+prompt` becomes a project tree of tickets, how phase tickets appear after
the spec merges, and which persona workers a ticket gets.

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
   to spawn" below):
   - `project:<slug>.research`: one or more research tickets.
   - `project:<slug>.design`: depends on the research tickets.
   - `project:<slug>.spec`: exactly one ticket, depends on design; it
     writes `SPEC.md` with the `.design` ticket's design folded in (see
     `l-spec-driven-development`, `references/spec-format.md`), opens the spec PR and gates
     with `+human-review-ready`.
   No separate testing tickets: testing runs inside each phase ticket.
   For every ticket it names the model/provider (small/cheap models for
   research, strong models for design, spec, implementation and review),
   plus one model/provider for the phase tickets to come.
2. From the plan, create the tickets:
   `task add project:<slug>.research +agent-task "technical research"`
   (repeat per ticket, per grouping). Every child gets `+agent-task`,
   since these are what future poll passes work. Wire
   `depends:` as above; independent research tickets stay
   dependency-free so they can run in parallel. Annotate each ticket with
   the model/provider the plan assigned it:
   `task <id> annotate "model: <model> provider: <provider>"`, and the
   `.spec` ticket also with the phase assignment:
   `task <id> annotate "phases: model: <model> provider: <provider>"`, so a
   later poll pass spawning this ticket's worker reads it directly
   instead of re-deriving it (the model rule in `../../l-multi-agent-mode/references/harness.md`).
3. If the project tracks work in GitHub issues, open the issue for the
   ask, or use the one the human filed, assigned to the human
   (`l-spec-driven-development`, `references/trace-and-github.md`), and annotate every created
   ticket `issue: #<n>`; the spec and phase PRs link it from there.
4. Write the plan itself to
   `tasks/context/design/<uuid8>-<slug>-intake.md` (uuid8 of the
   `+prompt` task) so the reasoning for the breakdown survives after the
   `+prompt` task closes.
5. Close the `+prompt` task immediately:
   `task <prompt-id> annotate "decomposed into project:<slug>.*: see tasks/context/design/<uuid8>-<slug>-intake.md"`
   then `task <prompt-id> done`. It was scope, not work; it never sits in
   the `+agent-task` queue itself.
6. Continue this same poll pass into the newly created tickets per the
   normal queue-poll procedure (SKILL.md): decomposition and the first
   claimable child(ren) can happen in the same pass.

**Phase tickets.** When the spec PR is merged, the agent creates one
phase ticket per `SPEC.md` Roadmap phase:
`task add project:<slug>.p<k> +agent-task "p<k>: <what runs after it>"`,
each `depends:` on the previous phase ticket, each annotated
`model: <model> provider: <provider>` from the `.spec` ticket's
`phases:` annotation, and `issue: #<n>` from it when one exists. If the `.spec` ticket carries none, run the
task-planner for the phase tickets first. Then `task <id> done` the
`.spec` ticket.

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
| research review | `l-persona-reviewer` | research-reviewer |
| design review | `l-persona-design-architecture` + optionally `l-persona-auditor-security` | design-reviewer(-sec) |
| spec review | `l-persona-reviewer` + `l-persona-auditor-security` for security-sensitive specs | spec-reviewer(-sec) |
| implementer | `l-persona-programmer` | implementer |
| code reviewer | `l-persona-reviewer` | reviewer |
| tester | `l-persona-tester` | tester |

Cross-check this table against `l-personas`' own list before spawning: it
drifts as personas are added/renamed; that skill's dynamic discovery
snippet is the source of truth, this table is only a pipeline-stage
convenience mapping over it.

Run every spawned research worker in parallel (Hermes: spawn all panes,
prompt all, then poll each with `herdr agent get <name>` until idle; Claude
Code: issue all Agent calls in one turn and await their completion
notifications) before moving to synthesis.

