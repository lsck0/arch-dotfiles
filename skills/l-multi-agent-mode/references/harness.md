# Workers: harness, mechanics, lifecycle

Shared by `l-multi-agent-mode` (live, one idea, no task db) and `l-multi-agent-task-mode` (self-polling queue).
Where the two modes differ, both variants are spelled out; read the one for the mode you run.

## Detect the harness once

```bash
test "${HERDR_ENV:-}" = 1
```

- `HERDR_ENV=1`: a live Herdr session. Workers are Hermes panes; use the Herdr column below.
- Otherwise Claude Code: workers are Agent tool calls running concurrently in the background. There is no
  `HERDR_ENV`, no panes, no `herdr` CLI, so skip every `herdr` command.

Pick the column once and use it for the whole run; never mix Hermes panes and Agent-tool workers. A `cronjob` has
neither a live Herdr session nor the Agent tool, so it cannot spawn workers: live mode cannot run there at all, task
mode hands unattended polling to the `l-single-agent-task-mode` cron (`l-agent-task-db`). The taskwarrior db, a
plain CLI, works the same under both harnesses.

## One harness, many roles

A worker differs only by its name, its prompt and the persona skill it carries, never by harness.

- Herdr: every worker is `--kind hermes`, never `--kind claude`/`codex`/`gemini` (not installed or verified here).
- Claude Code: every worker is an Agent call whose prompt tells it to load its `l-persona-*` skill (and the l-style
  parts) with the Skill tool before working.
- Skills per persona: workers that design or write code (`l-persona-design-*`, `l-persona-programmer`,
  `l-persona-reviewer`, `l-persona-tester`) also carry the `l-style` core plus `l-style-architecture`, because those
  personas lean on its principles without restating them; a tester adds `l-style-testing`, a latex/math worker
  `l-style-latex`. Research and audit personas run persona-only. A worker never sees a skill it was not given.
- Discover personas through `l-personas`, never from a hand-kept list.

## Model choice belongs to the task-planner

The `l-persona-orchestrator-task-planner` worker checks what is reachable right now and assigns a model (and, on
Hermes, a provider) to every worker, per `l-spec-driven-development`'s model sizing: small/cheap models for
research, strong ones for design, spec, implementation and review. The orchestrator only reads that assignment.

- Live mode reads it from `PLAN.md`.
- Task mode reads the ticket's annotation (`task <id> export`, the `.annotations[]` entry starting
  `model: <m> provider: <p>`). A ticket that skipped Intake (a human added `+agent-task` directly) gets one
  task-planner worker scoped to it first, which annotates the model and, without a `project:`, assigns one.
- Under Hermes the planner runs `hermes auth list`. Under Claude Code the model is the Agent call's `model` override
  and the provider is ignored. Local models (ollama, vllm) are for chat only, never a worker: Hermes has no local
  provider configured.

## Mechanics

Name every worker for its role (`research-market`, `research-codebase`, `design-architecture`, `design-reviewer`,
`programmer`/`implementer`, `reviewer`, `tester`, or a task-specific name): names are how prompts and reads target
it and how the human reads the team. Every worker writes its output to a durable file, never to pane or chat text,
and the orchestrator reads that file once the worker settles:

- live mode: `$SPEC_DIR/<STAGE>-<persona>.md` (the change's notes directory from `PLAN.md`);
- task mode: `tasks/context/{research,design}/<uuid8>-<slug>.md` or `tasks/agents/<uuid8>-<slug>/...`.

| operation | `HERDR_ENV=1` (Hermes panes) | Claude Code (Agent tool) |
|---|---|---|
| spawn | `herdr pane split --current --direction right --cwd "$REPO_DIR" --no-focus` (read `.result.pane.pane_id`), then `herdr agent start <name> --kind hermes --pane <id> --timeout 30000 -- -m <model> --provider <prov> -s <persona>[,l-style,l-style-architecture[,l-style-testing]]` | one Agent call per worker, `subagent_type` general-purpose, `model` from the plan or annotation; the prompt names the role, the skills to load, the output file, then "stop". Live mode may use `fork` to share the orchestrator's context; task mode never does, since a worker starts from the durable files |
| isolate parallel edits | `herdr worktree create`; the worker starts in the worktree's root pane (`.result.root_pane.pane_id`) and skips the split | `isolation: "worktree"` on the Agent call |
| drive / follow up | `herdr agent prompt <name> "<task, ending in: write to <file>, then stop>" --wait --timeout 120000` | `SendMessage` to the worker's id or name, context intact |
| wait | `--wait` blocks until it settles; else `herdr agent get <name>` until idle | no polling: a completion notification arrives |
| read the result | `cat <output file>` | the same |
| close | `herdr pane close <pane_id>`; `herdr worktree remove --workspace <id>` once its PR is open | a finished agent exits by itself; stop a stale one with `TaskStop <task_id>`; an unchanged worktree is cleaned automatically |

`-s <persona>[,l-style,...]` (Hermes) or the load-these-skills line (Claude Code) is what makes a worker that role.
A worker that launches an app only to screenshot or check it keeps it on its own headless output (skill
`l-dotfiles-gui-testing`): say so in its prompt.

Herdr notes: a bare `--kind hermes` start goes straight to `agent_status: idle`, unlike native CLIs with a trust
dialog. A start that times out or returns `agent_not_ready`: inspect with `herdr agent read <name> --source
recent-unwrapped --lines 40` and `herdr agent get <name>`. Never close a pane or remove a worktree you did not
create, and never `herdr server stop`.

Parallel research: spawn every research worker of a stage at once (Hermes: spawn all panes, prompt all, then poll
each with `herdr agent get <name>` until idle; Claude Code: all Agent calls in one turn) before synthesis.

## Lifecycle

A worker lives for one stage (in task mode: one stage of one ticket) plus the fix-loop rounds that follow it.

- **Record on spawn.** Live mode: append name and pane or agent id to `$SPEC_DIR/WORKERS.md`. Task mode, in the same
  beat as the spawn: `task <id> annotate "worker: <name> pane: <pane_id>"` (Herdr) or `"worker: <name> agent:
  <task_id>"` (Claude Code); the open `worker:` annotations are the workers it owns.
- **Finished.** Its file is read and the next stage started. Close it now unless the next stage prompts it again
  (the programmer gets the review), and drop the record (task mode: `task <id> denotate "worker: <name> ..."`).
- **Stale.** Every wait has a timeout: 30 minutes for research, design and review, 60 for implement and test. A
  worker is stale when it settles without writing its file after one follow-up, when it is `blocked` on a dialog
  (nobody answers it), or when it is still `working`/`unknown` at its timeout with no new output since the last
  check. Read its last output, close it, drop its record, and spawn a fresh worker for the stage. Live mode: stale
  twice on one stage, stop and report. Task mode: annotate `"worker <name> closed stale: <reason>"`, leave the stage
  tag so the next pass respawns; stale twice on one stage raises the clarification gate.
- **Orphans (task mode).** No worker outlives the pass that spawned it; the next pass resumes from files, never from a
  worker's context. At the start of a pass every recorded pane still in `herdr agent list` is an orphan: close it and
  denotate. Under Claude Code background agents end with their session, so only denotate.
- **End.** Close every worker still recorded before the final report (live) or at the end of the pass (task).
