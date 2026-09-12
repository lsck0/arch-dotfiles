---
name: l-spec-driven-development
description: "Agent programming workflow."
---

# l-spec-driven-development

Research, then design, then spec, then human approval, then build.
Load for real non-trivial features, bugs or investigations.

## Steps (drop what a small task doesn't need, keep the order)

0. Sync + branch. Fetch, and get onto the up-to-date base branch with a
   clean tree before anything else — `master` for trunk-based, `dev` where
   the repo has a `prod`/`dev` split (`l-style`'s Git section). `git fetch`,
   `git pull --rebase`, abort with a clear message if the tree is dirty or
   diverged rather than papering over it. Then start clean per the repo's
   convention: trunk-based small/solo -> work on the base with small
   commits; feature branches (stable or multiple people) -> a short-lived
   branch off the base. Create the spec namespace here too:
   `specs/spec-<number>-<feature-name>/`, or the project's own equivalent.
1. Research -> `RESEARCH.md` (code, logs, web/market/lit search).
2. Design -> `DESIGN.md` (architecture/API/data model/UI). Ask the human on anything that isn't yours to decide.
3. Review: fresh context, checked against the project's own guidelines.
4. Spec -> `SPEC.md`: TLDR, concepts, API signatures, data structures, algorithms, integration points. Enough that an implementer never has to ask.
5. Human review, iterate to explicit approval. This gate is the last
   planning artifact before implementation — `SPEC.md` when the task has
   one, otherwise the last doc that exists (`DESIGN.md` for a bug fix or
   anything small enough to skip a spec). Gate once, on whatever that
   final pre-build doc is; never build without the human's approval on it.
6. Roadmap -> `ROADMAP.md`: phases/tickets, each traceable to a spec section.
7. Implementation: work the roadmap. Hold every ticket/phase to the codebase's actual standards of correctness.
8. Land it, then stop. Commit to the codebase's convention (`l-style`'s Git
   section: conventional commits, one logical change per commit, every
   commit green).
   Trunk-based -> the small commits land on the base directly. Feature
   branch -> rebase onto the base, push, open a PR, then switch back to the
   base branch and leave the tree clean for the next task. Never leave the
   session parked on the feature branch. The PR is the stop point — the
   agent opens it and the run ends; the human reviews and merges. Don't
   merge, don't self-approve, don't wait on the PR for follow-up work.

## Human touchpoints

The human is in the loop at exactly three points; everything between them
runs autonomously.

1. **Input** — the human gives the initial prompt or GitHub issue (step 0).
2. **Plan approval** — the human approves the last planning artifact before
   the build: `SPEC.md`, or `DESIGN.md` when the task has no spec (step 5).
3. **PR review** — the agent opens the PR and stops; the human reviews and
   merges (step 8).

## Parallelism and model choice

An agent acting as an orchestrator (`l-multi-agent-mode`/ `l-multi-agent-task-mode`) should:

- size subagent count and model strength to the stage, small/cheap models for research, strong models for design and spec.
- start every step with a fresh context.
- communicate through markdown files in the spec directory.

At most 2 features implemented concurrently, and only when the repo is set
up as a bare repo with git worktrees so each feature gets its own isolated
working tree (the orchestration skills' worktree mechanics). Without
worktrees, two workers in one tree stomp each other's uncommitted changes
— implement sequentially instead. This is a tighter sub-cap on tree-
mutating implementation work; it sits under the orchestration skills'
general "up to 3 independent things at once" budget (`l-agent-task-db`),
which still governs research/design/review workers and plain tool calls.
