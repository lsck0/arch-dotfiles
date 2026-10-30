---
name: l-spec-driven-development
description: "Spec-driven workflow for real features, bugs and investigations: a specs/ corpus, full research then a phased spec, each phase landing as its own revertible PR with a trace back to its requirements. Owns the parallelism budget and the GitHub/branch/PR rules the task-mode skills reuse. Load for any non-trivial change in Luca's repos."
---

# l-spec-driven-development

Full research, then a spec with a phased roadmap, then the spec built
phase by phase. Every phase lands as its own reviewable PR, leaves the
system running, and can be reverted. Load for real non-trivial features,
bugs or investigations.

References, read at the step that names them:
[references/spec-format.md](references/spec-format.md) (every `SPEC.md`
section and the Roadmap table),
[references/trace-and-github.md](references/trace-and-github.md) (trace
names, PRs, reviewers, issues, waiting on a PR, branches),
[references/worktrees.md](references/worktrees.md) (parallel
implementation with Herdr worktrees).

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

Both modes share the stages, the phase rules, the trace and the GitHub rules
([references/trace-and-github.md](references/trace-and-github.md)). The agent never merges a spec PR: that merge is the
sign-off. In led mode the human merges every PR.

**Merge policy.** The project's `AGENTS.md` states who merges phase PRs:
`Merge policy: agent` (the agent merges once review, tests and CI pass)
or `Merge policy: human` (the agent asks the human to merge, and waits
for it). No line means `human`.

## Two build shapes

The stages below produce a spec and then build it. How the building is shaped depends on where the project is:

- **Incremental** (the default once anything must keep working): one capability at a time, each landing as its own
  revertible phase PR that leaves the system running (Phase loop, Phase rules). This is the shape for a live codebase, a
  shared repo, or anything past its MVP.
- **Whole-project, the pottery shape** (greenfield, pre-MVP, one owner): write one spec that encompasses the whole
  project up front, then throw the whole thing on the wheel. Implement every feature in a broad, deliberately rough
  first pass that need not keep anything running or revert cleanly, getting the full shape into existence. Then converge
  it by repetition: iterate, benchmark, test, refine, and again, shaving and perfecting pass after pass until it holds.
  Quality here comes from the refinement cycles, not from each step being final. This is why the pre-MVP git exemption
  exists (`l-style-tooling`, Git): the rough pass is allowed to be messy history. The moment the project has something
  worth keeping running, it graduates to the incremental shape, and the phase rules apply from then on.

Both shapes use the same spec corpus and the same stages; they differ only in whether the roadmap is built one
revertible phase at a time or thrown whole and then refined. Pick the shape that fits the project's stage, and say which
one when it is not obvious.

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

**Design** -> `DESIGN.md`: everything the SPEC.md sections need,
worked out: architecture, API, data model, UI, workflows, failure modes,
security, performance, accessibility, rejected alternatives. Reviewed.
Ask the human on anything that isn't yours to decide (led mode: that is
every real decision; autonomous mode: write the open question into the
spec PR, where the human signs it off). An uncertain external mechanism
(a framework's fixed-step mode, headless rendering, a new backend) is
de-risked by a throwaway spike with a written verdict before a phase
depends on it; the design records the spike result and names the fallback
if it fails.

**Spec** -> amend `SPEC.md` ([references/spec-format.md](references/spec-format.md)): every section, filled from
the reviewed design. New target requirements as unticked lines, the
phases that reach them as new Roadmap rows. Enough that an implementer
never has to ask and the human can sign off without reading anything
else. Reviewed against the section list: a spec missing a section is a
FAIL, and the spec gate does not open on it.

**Spec gate.** Commit the spec changes on a branch `spec/spec-<nnn>-<slug>`
and open a spec PR (with `INDEX.md` if a spec was added) per the GitHub
rules. Open questions go in a document, never in chat:
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
   one branch and worktree per workstream ([references/worktrees.md](references/worktrees.md)); the phase is done when
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
   open the PR as a draft per the GitHub rules, so CI runs on it.
4. Review, test, improve. A fresh-context reviewer checks the PR against
   the spec and the project's guidelines; a tester runs the spec's
   Testing section against the PR's branch, and CI runs on it. Every
   FAIL goes back to the implementer, and the fixes are pushed to the
   same PR. Repeat until the review is PASS, the tests pass, CI is green,
   and the phase rules below hold.
5. Merge. Mark the PR ready (`gh pr ready <n>`). Autonomous mode acts on
   the merge policy: `agent` merges (`gh pr merge <n> --rebase
   --delete-branch`); `human` comments that the PR is ready to merge and
   waits on it (GitHub rules, "Waiting on a PR"). A merge that branch protection blocks, for
   example on a required human approval, falls back to `human`; never
   bypass it. Led mode stops at the PR. After the merge the spec
   describes the merged code; clean up the branch (GitHub rules, Branches). A repo's own
   commit rule overrides steps 3 and 5 (e.g. `l-dotfiles`: never commit
   or push): stop at a reviewed working tree holding only the phase's
   changes and report instead; Sync's clean-tree check is waived there.
6. Report: phase, requirement IDs built, every link, how to run it, every
   check as passed, failed or not run. Never round "could not run" up to
   "passed". When the run leaves a process running or anything unverified
   (an autonomous run above all), the report is a handover note: what is
   running (pid, port, version), how to check, stop and resume it, the one
   command to resume, where screenshots are, and an explicit "not done or
   not checked" section. The owner must be able to pick it up cold.

The next phase starts only after this one merged. Trunk-based solo repos
may land a phase as commits on the base instead of a PR; the review and
tests still pass first. After the last phase, report the whole change:
every requirement built, every PR, every check.

**Feedback.** A PR the agent waits on gets a review or comment (spec PR,
or a phase PR the human is merging under `Merge policy: human` or chose
to inspect), or the human gives a PR link and says apply the feedback. Resolve the PR through its trace block, check out
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

## Parallelism and model choice

This section owns the parallelism rules for `l-multi-agent-mode`,
`l-multi-agent-task-mode` and `l-single-agent-task-mode`.

**Budget.** Up to 3 independent, non-blocking things at once: worker
panes, subagents, or plain tool calls (e.g. a web lookup alongside repo
scaffolding). A ceiling, not a target: run 1 when only 1 is workable.
Never start a 4th before one of the 3 finishes. Never parallelize a
dependency (a design review needs the design doc first); a dependency
chain stays sequential whatever the budget. Work forward one unit at a
time, parallel only where the units are genuinely independent, and bound
the parallelism by the machine's memory, not just this count: heavy
building or compiling agents each hold a real footprint, so on a large
build run at most two at once however much the budget would otherwise
allow.

**Implementer cap.** At most 2 workstreams implemented concurrently, each
in its own worktree ([references/worktrees.md](references/worktrees.md)). They count inside the budget of 3, not on
top of it; the remaining slot goes to research, design or review workers
and plain tool calls.

An agent acting as an orchestrator should:

- size subagent count and model strength to the stage, small/cheap models
  for research, strong models for design, spec, implementation and review.
- start every stage with a fresh context.
- communicate through markdown files in the spec directory.

