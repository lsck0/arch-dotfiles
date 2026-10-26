# Pipeline: files, stages, fix loop

Part of `l-multi-agent-task-mode`: where a claimed ticket's files live, which `+stage-*` tags each ticket kind goes
through, and the review/test loops.

## Directory layout for a claimed task

```
<project-root>/
  tasks/                                        # see l-agent-task-db
    context/
      questions/3f2a9c1d-dark-mode-toggle.md    # shared across ALL tasks
      research/3f2a9c1d-dark-mode-toggle.md
      design/3f2a9c1d-dark-mode-toggle.md
    agents/
      3f2a9c1d-dark-mode-toggle/
        review/{research-review,design-review,spec-review,code-review}.md
        implementation/report.md
        tests/report.md
```
Research/design findings go in `tasks/context/{research,design}/` (durable,
shared, human-readable project history per `l-agent-task-db`); review/
implementation/test artifacts that are pipeline-internal working state go
in `tasks/agents/<uuid8>-<slug>/`. uuid8 is the first 8 chars of the
task's uuid (`task _get <id>.uuid | cut -c1-8`); numeric ids are only for
immediate commands. Actual code changes for the implementer persona
happen in the REAL project tree at its real paths:
`implementation/report.md` records what changed and where, it is not a
copy of the code. Don't auto-commit: check for a skill governing this
repo's commit convention (e.g. `l-dotfiles`) same as any other edit.

## Stages per ticket

Every claimed ticket carries exactly one `+stage-*` tag while claimed
(vocabulary in `l-agent-task-db`), starting at `+stage-queued`:

| ticket | stages | done when |
|---|---|---|
| `.research` | queued -> research -> research-review | research review passed |
| `.design` | queued -> design -> design-review | design review passed |
| `.spec` | queued -> spec -> spec-review | spec PR merged by the human, phase tickets created |
| `.p<k>` | queued -> implement -> code-review -> test -> land | phase PR merged, per the merge policy |

`+stage-spec` covers writing every `SPEC.md` section
(`l-spec-driven-development`, `references/spec-format.md`); `+stage-spec-review` checks
that none is missing or thin before the spec PR opens. `+stage-implement`
ends with the phase's draft PR open; review and test run against it.
`+stage-land` covers the merge step of `l-spec-driven-development`'s
Phase loop: ready, merge per the project's merge policy, branch cleanup.

Completion follows `l-agent-task-db` ("Completion: `task <id> done`"):
the agent marks the ticket done itself.

## Fix loop

Per phase ticket, before IMPLEMENT: fetch, base branch up to date with a
clean tree (the previous phase merged), then a new branch
`<type>/spec-<nnn>-p<k>-<slug>` off the base, never off the spec branch
(`l-spec-driven-development`, Phase loop and Branches).

Two tickets implemented at once each get their own isolated worktree (`l-spec-driven-development`, `references/worktrees.md`; the
mechanics table's isolate row in `../../l-multi-agent-mode/references/harness.md`), within its 2-implementer cap, and
`tasks/context/` stays in the main checkout.

```
research ticket: RESEARCH -> RESEARCH-REVIEW
  FAIL -> researcher gets review/research-review.md -> RESEARCH -> RESEARCH-REVIEW
design ticket:   DESIGN -> DESIGN-REVIEW
  FAIL -> designer gets review/design-review.md -> DESIGN -> DESIGN-REVIEW
spec ticket:     SPEC -> SPEC-REVIEW
  FAIL -> spec author gets review/spec-review.md -> SPEC -> SPEC-REVIEW
  PASS -> spec PR, +human-review-ready
phase ticket:    IMPLEMENT -> draft PR -> REVIEW -> TEST -> LAND
  REVIEW FAIL -> implementer gets review/code-review.md -> push to PR -> REVIEW
  TEST FAIL   -> implementer gets tests/report.md -> push to PR -> REVIEW -> TEST
  TEST PASS + CI green -> LAND -> ready -> merge policy -> merged -> done
```
Stage tags follow the loop, swapped in one `task modify` each time. No
human gate inside a phase. LAND per `l-spec-driven-development`'s Phase
loop: spec updated in the same PR, trace block, run and revert lines,
`gh pr ready`, then the merge policy (`agent`: merge; `human`: wait on
the PR), then branch cleanup and back to the base with a clean tree.

A reviewer never approves its own work: the merge rests on a separate reviewer worker's PASS and the
tester's report. A repo whose convention forbids auto-committing
(e.g. `l-dotfiles`) -> stop at a clean, reviewed working tree and leave
the commit to the human, same deference as the "Don't auto-commit" rule
above. The ticket is `task <id> done` once its PR is merged (see
`l-agent-task-db`, "Completion").

Cleanup follows the lifecycle in `../../l-multi-agent-mode/references/harness.md`. Under Herdr, never close a pane or
remove a worktree without a `worker:` record from this skill, and never
`herdr server stop`.

