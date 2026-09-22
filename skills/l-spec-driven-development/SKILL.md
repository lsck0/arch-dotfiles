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

`specs/` describes the whole system, and the codebase is an
implementation of it. One spec per capability, long-lived:
`specs/spec-<nnn>-<slug>/` with `SPEC.md` (the system as it is, plus the
target) and `ROADMAP.md` (how we get from one to the other). A change
amends the specs it touches; it creates a new spec only when no existing
one covers the capability.

`specs/INDEX.md` maps every spec to the code implementing it:

```
| Spec | Capability | Implemented in | Last reconcile |
|---|---|---|---|
| spec-003-auth | login, sessions, tokens | `src/auth/` `src/http/session.rs` | 2026-09-20 @ a1b2c3d |
```

Code under no spec's `Implemented in` is unspecified: list it at the end
of `INDEX.md` until a spec covers it.

Corpus and code stay in sync, always. Every change to code under a
spec's `Implemented in` updates that spec in the same commit or PR,
inside this workflow or not (a one-line fix included). A spec that
disagrees with the code is a bug in one of them; find out which before
building on either.

## Two modes

- **Led** — the human is the orchestrator. They lead through the stages,
  take the design decisions and iterate on them with you. Stop and ask at
  every design decision, and after every stage and every phase. Nothing
  advances without them.
- **Autonomous** — an orchestrator skill (`l-multi-agent-mode`,
  `l-multi-agent-task-mode`) runs the stages. The human appears at three
  gates only; everything between them runs on its own:
  1. **Input** — the prompt or issue.
  2. **Spec** — they accept the spec PR or send feedback.
  3. **Result** — per phase, they look at the PR and the build it
     produced, then merge it or send feedback.

Both modes share the stages, the phase rules and the trace below. Whoever
merges, it is never the agent: no merge, no self-approval, no auto-merge.

## Stages (drop what a small task doesn't need, keep the order)

**Sync.** Fetch, get onto the up-to-date base branch (`master`
trunk-based, `dev` on a `prod`/`dev` repo, per `l-style`'s Git section)
with a clean tree. Abort with a clear message if the tree is dirty or
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

Research and design are notes for one change, not part of the
description: they live in `specs/spec-<nnn>-<slug>/notes/<date>-<change>/`,
their outcome lands in `SPEC.md` (requirements, Decisions), and they stay
only as the record behind a decision.

**Research** -> `RESEARCH.md`. Full, before any design: code, logs,
prior art, market. Every claim names what was read.

**Design** -> `DESIGN.md`: architecture, API, data model, UI, failure
modes, rejected alternatives. Ask the human on anything that isn't yours
to decide (led mode: that is every real decision).

**Review.** Fresh context, against the project's own guidelines.

**Spec** -> amend `SPEC.md` and `ROADMAP.md` (formats below): new target
requirements as unticked lines, the phases that reach them as new
roadmap rows. Enough that an implementer never has to ask. The human
approves both together.

**Spec gate.** Commit the spec changes on a branch `spec/spec-<nnn>-<slug>`
and open a spec PR (with `INDEX.md` if a spec was added). The human
accepts (merges) or sends feedback, which runs as Feedback. In led mode the human may approve in chat instead;
commit the spec with the first phase then. A bug fix or anything small
enough to skip a spec gates on `DESIGN.md` the same way.

**Phase loop.** For each roadmap phase, in order:
1. Branch `<type>/spec-<nnn>-p<k>-<slug>` off the updated base (after the
   previous phase merged). A phase split across parallel workstreams gets
   one branch and worktree per workstream (below); the phase is done when
   all of them merged.
2. Implement. Implementation makes no decisions: a behaviour choice the
   spec leaves open is a spec gap. Stop, name the requirement and the open
   choice, and hand it back to Spec. Tests carry the requirement ID in
   their name. A bug fix starts with a failing test that reproduces it;
   behaviour only visible on a running system is measured before and
   after with the same command.
3. Verify the phase rules below hold: build green, system runs, revert
   path known.
4. Land: conventional commits, one logical change each, every commit
   green; stage named paths only, never `git add -A`. Tick and cite the
   phase's requirements in `SPEC.md`, update `Implemented in` and
   `INDEX.md` when code moved, and set the phase's row in `ROADMAP.md`,
   all in the same PR: after merge the spec describes the merged code.
   Rebase, push, open the PR with the trace block, return the main checkout to the base branch (or remove the
   worktree), and stop.
5. Report: phase, requirement IDs built, every link, how to run it, every
   check as passed, failed or not run. Never round "could not run" up to
   "passed".

The next phase starts only after the human merged this one. Trunk-based
solo repos may land a phase as commits on the base instead of a PR; the
phase still ends at a stop for review.

**Feedback.** The human gives a PR link (spec or phase) and says apply
the feedback. Resolve the PR through its trace block (below), check out
its branch, and read everything: the human's points plus every review
comment, inline ones included (`gh pr view --comments` misses those;
`gh api repos/<owner>/<repo>/pulls/<n>/comments` has them). A point
nobody repeated still needs an answer.
- Spec PR -> edit `SPEC.md`/`ROADMAP.md`. Phase PR -> code, tests and the
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
  rules is split, or merged into its neighbour, in `ROADMAP.md`.

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
  Phase: p<k> of <n> (ROADMAP.md)
  Requirements: spec-<nnn>/R-004, spec-<nnn>/R-005
  Issue: #<n>
  Run: <preview URL | build-and-start command>
  Revert: <git revert <sha> | down migration + revert>
  ```
- **Commits** carry trailers `Spec: spec-<nnn>` and
  `Refs: spec-<nnn>/R-004, #<n>`.
- **Tests** carry the requirement in their name (`spec003_r004_...`), so
  a grep finds the proof after any refactor.
  The issue closes when the change is verified, not when a PR merges, so
  reference it rather than auto-closing it.
- **ROADMAP.md** rows link back: each phase lists its PRs and state.
- Resolving a PR: trace block first, branch name second. Neither present
  -> ask; don't guess the spec.

## SPEC.md

The system as it is, and the target. Before writing a new one, copy the
structure of the best existing spec in the corpus; don't invent a new
one, and don't imitate one that reads like a diary.

- **Header**: `Implemented in:` the code dirs/files, `Last reconcile:`
  date and commit.
- **Requirements** are one verifiable statement per line with a stable
  ID, present tense: `- [x] **R-012** <behaviour> (\`path#Symbol\`)` is
  true now and cited; `- [ ] **R-013** <behaviour>` is target. IDs are
  never reused or renumbered, since commits and tests cite them. Outside
  its own spec a requirement is written `spec-<nnn>/R-<nnn>`. A
  dropped requirement stays, struck through, pointing at what replaced it.
- **Failure modes**, numbered: trigger -> behaviour -> fail-closed or
  fail-open -> what the user sees.
- **Gaps**: every `[ ]` requirement, with what the code does instead and
  the roadmap phase or issue that closes it. An open requirement without
  a gap entry is a hidden promise.
- **Coverage table** last: `ID | implemented at (path#Symbol) | proven by
  (test) | done/gap`. The spec auditor and tester work from this table.
- **Bug fixes** add no requirement: a bug is a gap between an existing
  requirement and the code. If the fix shows a requirement is missing,
  add it to the governing spec.
- **Decisions**: the only place with dates and history. `- YYYY-MM-DD —
  <decision>. Rejected: <A> (<why>), <B> (<why>).`

Ticked lines describe the code as it is: every merge moves lines from
target to ticked. No "previously", "now fixed" or "next steps" in the
text: git has the history, `ROADMAP.md` has the way there.

## ROADMAP.md

```
| Phase | Delivers (requirements) | Depends on | PRs | State |
|---|---|---|---|---|
| p1 | R-001, R-002: <what runs after it> | — | #41 | merged |
| p2 | R-003: <...> | p1 | #44, #45 | in review |
| p3 | R-004, R-005: <...> | p2 | — | planned |
```

How the spec gets from as-is to target. Phase numbers keep counting up
across changes; merged rows stay as the link from requirements to PRs.
State is one of `planned`, `in progress`, `in review`, `merged`,
`reverted`. Each phase names what runs after it, so the phase rules can
be checked against it.

## Parallelism and model choice

An agent acting as an orchestrator (`l-multi-agent-mode`/
`l-multi-agent-task-mode`) should:

- size subagent count and model strength to the stage, small/cheap models
  for research, strong models for design and spec.
- start every stage with a fresh context.
- communicate through markdown files in the spec directory.

At most 2 workstreams implemented concurrently, each in its own worktree
(below). This is a sub-cap on tree-mutating work under the general "up to
3 independent things at once" budget (`l-agent-task-db`), which still
governs research/design/review workers and plain tool calls.

## Parallel implementation: one worktree per workstream

Two workers in one working tree stomp each other's uncommitted changes,
so every concurrent implementer gets its own checkout. Any repo works, no
bare-repo setup needed. Use Herdr's worktree support, not raw
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
  deletes the checkout and its workspace and keeps the branch for the PR.
  Feedback on that PR reopens it with `herdr worktree create --branch
  <existing branch>` or `open`.
  `create` also opens a workspace for the main checkout if none exists;
  close that with `herdr workspace close <id>` when you opened it.
- Only one implementer at a time needs no worktree: it works in the main
  checkout.
