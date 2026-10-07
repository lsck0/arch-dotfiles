---
name: l-spec-driven-development
description: "Agent programming workflow."
---

# l-spec-driven-development

Full research, then a spec with a phased roadmap, then the spec built
phase by phase. Every phase lands as its own reviewable PR, leaves the
system running, and can be reverted. Load for real non-trivial features,
bugs or investigations.

## The spec corpus

`specs/` describes the whole codebase, and the codebase is an
implementation of it. Someone who reads only `specs/` knows what the
system does, why, and how it is built. One spec per capability,
long-lived: `specs/spec-<nnn>-<slug>/SPEC.md`. One file holds everything
about the capability: why it exists, what it must do, how it is built,
its security, performance and accessibility, how it is tested, rolled
out and rolled back, and the roadmap from the system as it is to the
target. A change amends the specs it touches, rewriting their sections
to describe the new state rather than appending to them; it creates a new
spec only when no existing one covers the capability.

`specs/INDEX.md` maps every spec to the code implementing it:

```
| Spec | Capability | Implemented in | Last reconcile |
|---|---|---|---|
| spec-003-auth | login, sessions, tokens | `src/auth/` `src/http/session.rs` | 2026-09-20 @ a1b2c3d |
```

Code under no spec's `Implemented in` is unspecified: list it at the end
of `INDEX.md`. That list is debt, not a resting place: a change that
touches unspecified code writes or extends the spec that covers it.

Corpus and code stay in sync, always. Every change to code under a
spec's `Implemented in` updates that spec in the same commit, inside
this workflow or not (a one-line fix included). A spec that
disagrees with the code is a bug in one of them; find out which before
building on either.

## Two modes

- **Led**: the human is the orchestrator. They lead through the stages,
  take the design decisions and iterate on them with you. Stop and ask at
  every design decision, and after every stage and every phase. Nothing
  advances without them.
- **Autonomous**: an orchestrator skill (`l-multi-agent-mode`,
  `l-multi-agent-task-mode`) runs the stages unattended
  (`l-single-agent-task-mode` works only directly workable tickets and
  hands a full spec pipeline to `l-multi-agent-task-mode`). The human
  reviews at two gates only; everything else runs on its own:
  1. **Input**: the prompt or issue.
  2. **Spec**: they sign off the spec PR or send feedback.
  After the spec sign-off the human does not read code. Phases are
  implemented, reviewed and tested by the agents, and merged per the
  project's merge policy (below): under `Merge policy: human` the human
  also merges each phase PR, without reading its code. The human gets
  the final report. The
  spec is the contract they signed, so the only thing that brings them
  back is a change to it (Phase loop, step 2).

Both modes share the stages, the phase rules, the trace and the GitHub
rules below. The agent never merges a spec PR: that merge is the
sign-off. In led mode the human merges every PR.

**Merge policy.** The project's `AGENTS.md` states who merges phase PRs:
`Merge policy: agent` (the agent merges once review, tests and CI pass)
or `Merge policy: human` (the agent asks the human to merge, and waits
for it). No line means `human`.

## Stages (drop what a small task doesn't need, keep the order)

**Sync.** Fetch, get onto the up-to-date base branch (`master`
trunk-based, `dev` on a `prod`/`dev` repo, per `l-style-tooling`'s Git
section, or whatever the project's branching convention names) with a
clean tree. Abort with a clear message if the tree is dirty or
diverged. Find the governing specs in `specs/INDEX.md`, or create the
next `specs/spec-<nnn>-<slug>/` when nothing covers the capability (a repo
without a corpus gets `specs/` and `INDEX.md` now). `spec-<nnn>` is the ID
everything below traces to.

**Reconcile.** Before designing on an existing spec, check it against
the code: citations still resolve, ticked requirements still hold,
`Implemented in` still matches. Drift gets fixed first, in the spec or as
a known gap, as its own commit; then stamp `Last reconcile` with the date
and `git log -1 --format=%h -- <implemented-in dirs>`. Stamp only after
actually reading the code.

Research and design drafts are working notes for one change: they live in
`specs/spec-<nnn>-<slug>/notes/<date>-<change>/`. Research stays there as
the record behind a decision. The design does not: Spec moves it into
`SPEC.md` in full, so an implementer never reads the notes.

Every stage's output is reviewed before the next stage starts: a
fresh-context reviewer checks it against the project's guidelines and
the ask, and writes PASS or FAIL. A FAIL goes back to the stage's author
with the review, and the stage runs again.

**Research** -> `RESEARCH.md`. Full, before any design: code, logs,
prior art, market. Every claim names what was read. Reviewed.

**Design** -> `DESIGN.md`: everything the SPEC.md sections below need,
worked out: architecture, API, data model, UI, workflows, failure modes,
security, performance, accessibility, rejected alternatives. Reviewed.
Ask the human on anything that isn't yours to decide (led mode: that is
every real decision; autonomous mode: write the open question into the
spec PR, where the human signs it off).

**Spec** -> amend `SPEC.md` (format below): every section, filled from
the reviewed design. New target requirements as unticked lines, the
phases that reach them as new Roadmap rows. Enough that an implementer
never has to ask and the human can sign off without reading anything
else. Reviewed against the section list: a spec missing a section is a
FAIL, and the spec gate does not open on it.

**Spec gate.** Commit the spec changes on a branch `spec/spec-<nnn>-<slug>`
and open a spec PR (with `INDEX.md` if a spec was added) per the GitHub
rules below. Open questions go in a document, never in chat:
`notes/<date>-<change>/QUESTIONS.md`, committed in the spec PR, one
question per section with the options and a recommendation, so the
human answers each one in a review comment on its line. Then wait on the
PR: the human signs off (merges) or sends
feedback, which runs as Feedback. In led mode the human
may approve in chat instead; commit the spec with the first phase then.
A bug fix or anything small enough to skip a spec gates on `DESIGN.md`
the same way.

**Phase loop.** For each roadmap phase, in order:
1. Branch `<type>/spec-<nnn>-p<k>-<slug>` off the updated base (after the
   previous phase merged), never off the spec branch or another phase's
   branch. A phase split across parallel workstreams gets
   one branch and worktree per workstream (below); the phase is done when
   all of them merged.
2. Implement. Implementation makes no decisions: a behaviour choice the
   spec leaves open is a spec gap. Stop, name the requirement and the open
   choice, and hand it back to Spec. In autonomous mode the spec author
   closes the gap: the amendment and its Decisions entry ship in the
   phase PR and are reviewed with it. Only a gap whose answer drops or
   contradicts a signed-off requirement goes back to the human, as a
   spec PR. Tests carry the requirement ID in
   their name. A bug fix starts with a failing test that reproduces it;
   behaviour only visible on a running system is measured before and
   after with the same command.
3. Open the PR. Conventional commits, one logical change each, every
   commit green; stage named paths only, never `git add -A`. Tick and
   cite the phase's requirements in `SPEC.md` and update `Implemented in`
   and `INDEX.md` when code moved, in the same commit as that code; set
   the phase's Roadmap row in `SPEC.md` in the same PR. Rebase, push, and
   open the PR as a draft per the GitHub rules below, so CI runs on it.
4. Review, test, improve. A fresh-context reviewer checks the PR against
   the spec and the project's guidelines; a tester runs the spec's
   Testing section against the PR's branch, and CI runs on it. Every
   FAIL goes back to the implementer, and the fixes are pushed to the
   same PR. Repeat until the review is PASS, the tests pass, CI is green,
   and the phase rules below hold.
5. Merge. Mark the PR ready (`gh pr ready <n>`). Autonomous mode acts on
   the merge policy: `agent` merges (`gh pr merge <n> --rebase
   --delete-branch`); `human` comments that the PR is ready to merge and
   waits on it (below). A merge that branch protection blocks, for
   example on a required human approval, falls back to `human`; never
   bypass it. Led mode stops at the PR. After the merge the spec
   describes the merged code; clean up the branch (below). A repo's own
   commit rule overrides steps 3 and 5 (e.g. `l-dotfiles`: never commit
   or push): stop at a reviewed working tree holding only the phase's
   changes and report instead; Sync's clean-tree check is waived there.
6. Report: phase, requirement IDs built, every link, how to run it, every
   check as passed, failed or not run. Never round "could not run" up to
   "passed".

The next phase starts only after this one merged. Trunk-based solo repos
may land a phase as commits on the base instead of a PR; the review and
tests still pass first. After the last phase, report the whole change:
every requirement built, every PR, every check.

**Feedback.** A PR the agent waits on gets a review or comment (spec PR,
or a phase PR the human is merging under `Merge policy: human` or chose
to inspect), or the human gives a PR link and says apply the feedback. Resolve the PR through its trace block (below), check out
its branch, and read everything: the human's points plus every review
comment, inline ones included (`gh pr view --comments` misses those;
`gh api repos/<owner>/<repo>/pulls/<n>/comments` has them). A point
nobody repeated still needs an answer.
- Spec PR -> edit `SPEC.md`. Phase PR -> code, tests and the
  spec's current-state sections together.
- One commit per point, in the given order, so the second review sees
  where each objection went. A point that is already true gets no commit,
  just the `file:line` showing it.
- Don't comply with a point that contradicts the approved spec, or asks
  for a decision rather than a change: name the requirement it conflicts
  with and ask. An accepted design change goes into `SPEC.md` and its
  Decisions section first, then the code.
- Re-run the checks, push, and post one PR comment mapping each point to
  its commit, to "already true at `file:line`", or to why not. Stop again
  at the PR.

## Phase rules

- **Still running.** After every phase the system builds, starts and
  does everything it did before. Unfinished behaviour is unreachable
  (not wired up, or behind a flag that defaults off), never half-exposed.
- **Revertible.** A phase reverts cleanly: the PR is one revertable unit
  (`git revert` of its merge or squash commit), data migrations ship with
  their down step or are additive only, and nothing in a later phase is
  required to undo it. The PR states how to revert.
- **Reviewable as a build.** The PR says how to see it running: the
  preview/staging URL where CI or deploy produces one, otherwise the exact
  command to build and start it locally.
- Small enough to review in one sitting. A phase that can't meet these
  rules is split, or merged into its neighbour, in the Roadmap.

## Trace

Every artifact names where it came from, so a bare PR link is enough to
find the spec, the phase and the requirements.

- **Code**: `INDEX.md` maps every file to its spec, so a diff alone
  names the specs it must update.
- **Branches**: `spec/spec-<nnn>-<slug>`, `<type>/spec-<nnn>-p<k>-<slug>`.
- **PR title**: `spec(spec-<nnn>): <title>`,
  `<type>(spec-<nnn>): p<k> <what is now true>`.
- **PR body** opens with the trace block:
  ```
  Spec: specs/spec-<nnn>-<slug>/SPEC.md (plus any other spec it touches)
  Phase: p<k> of <n> (SPEC.md Roadmap)
  Requirements: spec-<nnn>/R-004, spec-<nnn>/R-005
  Issue: #<n>
  Run: <preview URL | build-and-start command>
  Revert: <git revert <sha> | down migration + revert>
  ```
- **Commits** carry trailers `Spec: spec-<nnn>` and
  `Refs: spec-<nnn>/R-004, #<n>`.
- **Tests** carry the requirement in their name (`spec003_r004_...`), so
  a grep finds the proof after any refactor.
- **Issues**: PRs and commits reference the issue (`Issue:`, `Refs
  #<n>`). Only the last phase PR of the change says `Closes #<n>`: its
  merge comes after the last review and tests, so the issue closes when
  the change is verified.
- **Roadmap** rows link back: each phase lists its PRs and state.
- Resolving a PR: trace block first, branch name second. Neither present
  -> ask; don't guess the spec.

## GitHub: PRs, reviewers, issues, waiting

- **Questions** are documents: `QUESTIONS.md` in the spec PR (Spec
  gate), or under `l-agent-task-db` a question file in
  `tasks/context/questions/`. Never a chat prompt the human has to be
  present for.
- **Reviewer and assignee.** Every PR requests the human as reviewer and
  is assigned to them: `gh pr create --reviewer <login> --assignee
  <login>`, plus `--draft` for a phase PR (step 3 of the Phase loop); a
  spec PR opens ready for review. `<login>` is the `Reviewer:` line in `AGENTS.md`, else the
  repo owner (`gh repo view --json owner -q .owner.login`). GitHub
  refuses a review request to the PR's own author; when the agent pushes
  as the human, the assignee carries it.
- **Issues.** A project that tracks work in issues gets one per change:
  the issue the human filed, or one the agent opens from the prompt
  before the spec PR (`gh issue create --assignee <login>`). It
  stays assigned to the human (`gh issue edit <n> --add-assignee
  <login>`) for its whole life. Every PR of the change links it (Trace,
  above), and the issue gets a comment linking each new PR, so either
  side reaches the other.
- **Waiting on a PR.** The human never reports back by hand. Watch the
  PR itself until it merges, closes, or gets a new review or comment
  (any of them changes `updatedAt`):
  ```bash
  t0=$(gh pr view <n> --json updatedAt -q .updatedAt)
  while [ "$(gh pr view <n> --json state,updatedAt -q '.state+" "+.updatedAt')" = "OPEN $t0" ]; do
    sleep 120
  done
  ```
  Under Claude Code run it as a background command, so its exit wakes the
  orchestrator; a task-mode poll pass checks the same state instead.
  Merged -> continue. Closed unmerged -> stop and report. New activity ->
  read every review and comment, inline ones included, and run Feedback;
  if the activity was the agent's own push or comment, watch again.

## Branches

- Know the branch before every commit: `git branch --show-current`. A
  commit on the wrong branch is moved before anything else happens.
- One branch per PR. The spec PR lives on `spec/spec-<nnn>-<slug>`; every
  phase gets a new branch off the updated base after the previous PR
  merged. Never stack a phase on the spec branch or on an unmerged phase.
- Follow the project's branching convention: feature branches where it
  uses them, trunk commits where it lands on trunk.
- Clean up after every merge: delete the remote branch (`--delete-branch`
  on merge, or `git push origin --delete <branch>`), delete the local one
  (`git branch -d <branch>`), remove its worktree, and `git fetch
  --prune`. A bare-repo layout (`<repo>.git` with one worktree per
  branch) removes the worktree with `git worktree remove <path>` before
  deleting the branch.

## SPEC.md

Everything there is to know about one capability, as it is and as it
will be. It goes deep: why the feature exists, what it must do, how it
is built, what it costs, what it endangers, who it shuts out, and how it
ships and unships. Before writing a new one, copy the structure of the
best existing spec in the corpus; don't invent a new one, and don't
imitate one that reads like a diary.

Sections, in this order. Every spec has every section. A section that
does not apply says why in one line; it is never dropped silently.

- **Header**: `Implemented in:` the code dirs/files, `Last reconcile:`
  date and commit.
- **Purpose**: why the capability exists. The problem, who has it, what
  the capability must accomplish for them, how success is measured, and
  the non-goals.
- **Requirements** are one verifiable statement per line with a stable
  ID, present tense: `- [x] **R-012** <behaviour> (\`path#Symbol\`)` is
  true now and cited; `- [ ] **R-013** <behaviour>` is target. IDs are
  never reused or renumbered, since commits and tests cite them. Outside
  its own spec a requirement is written `spec-<nnn>/R-<nnn>`. A
  dropped requirement stays, struck through, pointing at what replaced it.
- **Design**: architecture, data flow, data model, API, UI, each part
  naming the requirements it serves. It describes one shape: the code as
  it is plus the target parts, marked by their unticked requirement IDs.
  Rejected alternatives go to Decisions, not here.
- **Workflows**: what users and developers do with it, step by step.
  Which workflows it adds, which it changes, and which it breaks or
  removes, with the migration path for each broken one.
- **Impact**: how the design fits into the existing project. Which
  modules and other specs it touches (and amends in the same PR), new
  dependencies, compatibility, data migration, and what it constrains
  later.
- **Failure modes**, numbered: trigger -> behaviour -> fail-closed or
  fail-open -> what the user sees.
- **Security**: assets, trust boundaries, who can reach what, the
  threats (abuse, injection, escalation, leaks, supply chain) and the
  mitigation for each, secrets handling, what is logged and what never
  is.
- **Performance**: the budgets (latency, throughput, memory, binary
  size, startup) with numbers, the hot paths, the scaling limit, and how
  each budget is measured.
- **Accessibility**: keyboard and screen-reader use, contrast, motion,
  text scaling, localization. A capability with no UI says so and names
  any UI it feeds.
- **Observability**: what makes each requirement's failure visible and
  explainable: the asserts on its invariants, the log events, the trace
  spans and perf scopes on its paths, the counters and capacity gauges,
  and what a failing test prints (`l-style-testing`).
- **Testing**: how each requirement is proven, by kind (simulation,
  property, fuzz, table-driven, unit, per `l-style-testing`), the exact
  commands that run them, and what a phase must pass before it merges.
- **Roadmap**: the phase table below: the steps from as-is to target.
- **Rollout**: how each phase reaches users. Flags and their defaults,
  migration order, deploy steps, who sees what when, and the signals
  (logs, metrics, errors) that say it works or must stop.
- **Rollback**: per phase, the exact undo: `git revert` of the merge,
  down migration, flag off, data repair. Name any point of no return and
  what guards it.
- **Gaps**: every `[ ]` requirement, with what the code does instead and
  the roadmap phase or issue that closes it. An open requirement without
  a gap entry is a hidden promise.
- **Decisions**: the only place with dates and history. `- YYYY-MM-DD:
  <decision>. Rejected: <A> (<why>), <B> (<why>).`
- **Coverage table** last: `ID | implemented at (path#Symbol) | proven by
  (test) | done/gap`. The spec auditor and tester work from this table.

Bug fixes add no requirement: a bug is a gap between an existing
requirement and the code. If the fix shows a requirement is missing, add
it to the governing spec.

Ticked lines describe the code as it is: every merge moves lines from
target to ticked. No "previously", "now fixed" or "next steps" in the
text: git has the history, the Roadmap has the way there.

### Roadmap

```
| Phase | Delivers (requirements) | Depends on | PRs | State |
|---|---|---|---|---|
| p1 | R-001, R-002: <what runs after it> | none | #41 | merged |
| p2 | R-003: <...> | p1 | #44, #45 | in review |
| p3 | R-004, R-005: <...> | p2 | none | planned |
```

How the spec gets from as-is to target. Phase numbers keep counting up
across changes; merged rows stay as the link from requirements to PRs.
State is one of `planned`, `in progress`, `in review`, `merged`,
`reverted`. Each phase names what runs after it, so the phase rules can
be checked against it.

## Parallelism and model choice

This section owns the parallelism rules for `l-multi-agent-mode`,
`l-multi-agent-task-mode` and `l-single-agent-task-mode`.

**Budget.** Up to 3 independent, non-blocking things at once: worker
panes, subagents, or plain tool calls (e.g. a web lookup alongside repo
scaffolding). A ceiling, not a target: run 1 when only 1 is workable.
Never start a 4th before one of the 3 finishes. Never parallelize a
dependency (a design review needs the design doc first); a dependency
chain stays sequential whatever the budget.

**Implementer cap.** At most 2 workstreams implemented concurrently, each
in its own worktree (below). They count inside the budget of 3, not on
top of it; the remaining slot goes to research, design or review workers
and plain tool calls.

An agent acting as an orchestrator should:

- size subagent count and model strength to the stage, small/cheap models
  for research, strong models for design, spec, implementation and review.
- start every stage with a fresh context.
- communicate through markdown files in the spec directory.

## Parallel implementation: one worktree per workstream

Two workers in one working tree stomp each other's uncommitted changes,
so every concurrent branch gets its own worktree. A project already laid
out as a bare repo with one worktree per branch keeps that layout; any
other repo works too. Use Herdr's worktree support, not raw
`git worktree`, so checkout, branch and pane are created together:

```bash
herdr worktree list                                  # reuse before creating
herdr worktree create --cwd "$REPO_DIR" --branch <workstream-branch> \
  --label <workstream-name> --no-focus --trust-repository
# -> .result.worktree.path            the worker's checkout
#    .result.root_pane.pane_id        start the worker here, no split
#    .result.workspace.workspace_id   needed for remove
herdr worktree open --path <existing-worktree>       # reopen after a restart
```

- The branch is the workstream's phase branch; land it from inside the
  worktree (rebase, push, PR).
- Specs, research and other shared docs stay in the main checkout's
  `$SPEC_DIR`; pass the worker that absolute path.
- After the PR is open: `herdr worktree remove --workspace <id>`. It
  deletes the checkout and its workspace and keeps the branch for the PR;
  the branch goes after the merge (Branches, above).
  Feedback on that PR reopens it with `herdr worktree create --branch
  <existing branch>` or `open`.
  `create` also opens a workspace for the main checkout if none exists;
  close that with `herdr workspace close <id>` when you opened it.
- Only one implementer at a time needs no worktree: it works in the main
  checkout.
