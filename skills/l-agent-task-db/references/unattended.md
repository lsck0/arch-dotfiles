# Unattended polling: the orchestrator profile and the backoff cron

Part of `l-agent-task-db`: where self-polling runs and how its cadence adjusts itself.

## The `orchestrator` Hermes profile: where self-polling runs

A Hermes process's profile is fixed at launch: nothing a skill does
mid-session can switch it, and the in-session `cronjob` tool has no
profile argument; it acts on the profile running it. So the
orchestrator's context settings are solved by LAUNCHING the self-polling
process under the right profile, not by anything a skill tells itself
once running.

The dotfiles provision that profile in `configs/programming/hermes/mod.nu`
(its `link` verb, run by `dot apply`): a Hermes profile named `orchestrator`,
cloned from `default` (same model/provider/skills/`.env`), with
`compression.threshold_tokens: 500000` set ONLY in that profile's
`config.yaml`, and the alias `hermes-orchestrator` (`hermes -p
orchestrator`). Compressing an orchestrator's chat history is safe because
its real state lives in `tasks/` (the taskwarrior db plus
`tasks/context/`). `default` (interactive chat) is never touched.

Any self-polling orchestrator process (a background loop, or the backoff
poll cron below) is launched under this profile, never `default`. Herdr
workers stay on the profile of the session that spawned them. A live
session already running under `default` (a human invoking one of these
skills in chat) stays on `default`: there is no way to hop profiles
mid-conversation, and a live chat has a human present who benefits from
full context.

## Self-adjusting backoff poll cron

When a project's queue relies on a cron nudge rather than a human
re-triggering a live pass, the poll cadence adjusts itself instead of
polling at a fixed rate forever or needing the human to wake it after
answering a question. The body of every run is `l-single-agent-task-mode`.

- **State file**: `tasks/.poll-backoff`: a single integer, the current poll
  interval in minutes (1 after progress, +1 per idle run). Gitignored,
  local state, same as `tasks/.task/`.
- **Setup (once per project)**: create a recurring job under the
  `orchestrator` profile with the CLI, not the `cronjob` tool (that tool
  acts on the profile of the session doing the setup, likely `default`).
  Then bake the returned job id into its prompt, since a run does not
  otherwise know its own id:
  ```bash
  hermes-orchestrator cron create "every 1m" "<prompt>" --name "poll <project>" \
    --skill l-single-agent-task-mode --workdir <project-root>
  hermes-orchestrator cron edit <job-id> --prompt "<prompt, naming job id <job-id>>"
  ```
  The schedule is a recurring interval (`every <N>m`), never a one-shot
  `in <N>m`: a one-shot job retires once its run ends, even when the run
  rescheduled it.
- **Inside each run**: the session executing it already belongs to the
  `orchestrator` profile (a job lives in the cron store of the profile
  that created it), so the `cronjob` tool is the right one to reschedule
  itself: `cronjob(action="update", job_id="<job-id>", schedule="every <N>m")`.
- **End of every run**:
  - Progress happened this pass (claimed new work, folded in an answered
    question, a waited-on PR merged or got feedback, a ticket advanced) ->
    write `1` to `.poll-backoff` and reschedule to `every 1m`.
  - No progress was possible (everything workable waits on an unanswered
    question or an unchanged PR) -> read the current N from
    `.poll-backoff` (default 1), write `N+1`, reschedule to `every <N+1>m`.
- Linear backoff, not exponential (1, 2, 3, 4... minutes), so a
  long-blocked project still gets checked at a bounded, predictable rate.
  The human never kicks the job after answering a question file; it comes
  back on its own within the current backoff window and snaps back to
  1-minute checks the moment it finds progress.
