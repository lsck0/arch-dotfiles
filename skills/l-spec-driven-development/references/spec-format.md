# SPEC.md format

Part of `l-spec-driven-development`: the sections every `SPEC.md` has and the Roadmap table.

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
- **Decisions**: the only place with dates and history. `- YYYY-MM-DD
  (<owner>): <decision>. Rejected: <A> (<why>), <B> (<why>).` Carry who
  made it, not just when; an agent-proposed decision reads "proposed,
  needs confirmation" until the owner confirms it. A reversal is a new
  dated line that keeps the old one and names what flipped it, never an
  edit over the original.
- **Coverage table** last: `ID | implemented at (path#Symbol) | proven by
  (test) | done/gap`. The spec auditor and tester work from this table.

Bug fixes add no requirement: a bug is a gap between an existing
requirement and the code. If the fix shows a requirement is missing, add
it to the governing spec.

Ticked lines describe the code as it is: every merge moves lines from
target to ticked. No "previously", "now fixed" or "next steps" in the
text: git has the history, the Roadmap has the way there.

## Roadmap

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

