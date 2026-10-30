# Unattended polling: the orchestrator profile and the backoff cron

Part of `l-agent-task-db`: where self-polling runs and how its cadence adjusts itself.

## The `orchestrator` Hermes profile: where self-polling runs

A Hermes process's profile is fixed at launch: nothing a skill does
mid-session can switch it, and neither the `cronjob` MCP tool nor `herdr
agent start` take a profile argument; both operate against whichever
profile is already running them. So the orchestrator's context settings
have to be solved by LAUNCHING the self-polling process under the right
profile, not by anything a skill instructs itself to do once running.

The dotfiles provision that profile in `configs/programming/hermes/mod.nu`
(its `link` verb, run by `dot apply`): a Hermes profile named `orchestrator`,
cloned from `default` (same model/provider/skills/`.env`), with
`compression.threshold_tokens: 500000` set ONLY in that profile's
`config.yaml`. Compressing an orchestrator's chat history is safe because
its real state lives in `tasks/` (the taskwarrior db plus
`tasks/context/`). `default` (interactive chat) is never touched.

**Any self-polling orchestrator process (a background loop, or the
backoff poll cron below) should be launched under this profile**, not
`default`:
```bash
HERMES_HOME="${HOME}/.hermes/profiles/orchestrator" hermes cron create ...
# or, equivalently, using the profile's own alias:
hermes-orchestrator cron create ...
```
Herdr workers are not launched per profile: `herdr agent start` takes no
profile, so live workers stay on the profile of the session that spawned
them. A LIVE session already running under `default` (e.g. a human
talking to Hermes directly in chat, invoking one of these skills
interactively) stays on `default` for that turn; there is no way to hop
profiles mid-conversation, and a live chat has a human present who
benefits from full context. Reserve `orchestrator` for processes that are
themselves self-polling/unattended.

## Self-adjusting backoff poll cron (unattended queue polling)

When a project's queue relies on a `cronjob` nudge rather than a human
re-triggering a live pass, the poll cadence must self-adjust instead of
polling at a fixed rate forever or requiring the human to manually "wake"
it back up after answering a question:

- **State file**: `tasks/.poll-backoff`: a single integer, the current poll
  interval in minutes (1 after progress, +1 per idle run). Gitignored,
  local state, same as `tasks/.task/`.
- **Setup (once per project)**: create the poll job UNDER THE
  `orchestrator` PROFILE (see above) with `schedule="in 1m"`. Use the
  `hermes cron create` CLI with `HERMES_HOME` set (or the
  `hermes-orchestrator` alias), not the `cronjob` MCP tool, since that
  tool is bound to whatever profile is running the CURRENT session (the
  one doing the setup, likely `default`). Then immediately edit it to bake
  its own returned job id into its prompt (a job doesn't otherwise know
  its own id), so every run can reschedule itself.
- **Inside each run**: once the job fires, the session executing
  it already belongs to the `orchestrator` profile (a job lives in
  whichever profile's cron store created it), so the `cronjob` MCP tool
  IS the right tool to reschedule itself at that point. `HERMES_HOME` only
  matters at initial setup time from a different (e.g. `default`)
  session.
- **End of every run**:
  - Progress happened this pass (claimed new work, folded in an answered
    question, a waited-on PR merged or got feedback, a stage advanced) ->
    write `1` to `.poll-backoff` and reschedule to `in 1m`.
  - No progress was possible (everything workable waits on an unanswered
    question or an unchanged PR) -> read current N from `.poll-backoff` (default 1),
    write `N+1`, and reschedule to `in {N+1}m`.
- Linear backoff, not exponential (1, 2, 3, 4... minutes), so a
  long-blocked project still gets checked at a bounded, predictable rate.
  The human never has to manually kick the job after answering a
  question file; it comes back on its own within the current backoff
  window and snaps back to 1-minute checks the instant it finds progress
  again.

