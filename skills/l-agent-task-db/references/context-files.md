# `tasks/context/` and question files

Part of `l-agent-task-db`: the durable docs behind every ticket and the shape of a question file.

```
tasks/context/
  research/<uuid8>-<slug>.md      # findings, spikes, investigation notes
  design/<uuid8>-<slug>.md        # design notes and decisions behind a change
  questions/<uuid8>-<slug>.md     # open questions blocking a +human-clarification-needed task
```
The specs themselves live in the repo's spec corpus (`specs/`, see
`l-spec-driven-development`); `tasks/context/` holds the notes behind a
change, in place of the corpus's `notes/` directory. Name every
long-lived file or dir `<uuid8>-<slug>`, where uuid8 is the first 8
characters of the task's uuid (see Pitfalls):
```bash
task _get 14.uuid | cut -c1-8     # -> 3f2a9c1d
```
This directory is the durable record of WHY decisions were made and WHAT
was found: not agent conversation history, and not taskwarrior
annotations beyond a pointer to the file. Record the file's path as a
task annotation the moment it's created:
```bash
task 14 annotate "context: tasks/context/research/3f2a9c1d-dark-mode-toggle.md"
```

## Question file shape

```markdown
# Task 3f2a9c1d: Dark mode toggle
Stage: design
Asked: 2026-09-04

## Q1: Local accounts or OAuth?
This affects the API, data model, security model, and deployment
architecture.
Recommendation: OAuth.

**Your answer:**

```
One `## Q<n>` section per open decision, each with the same "why this
needs human judgment + a recommendation" framing a design-review gate
would use. Never ask trivial questions this way: if it doesn't
materially change the design, decide it and record the reasoning in
`design/` instead of blocking on it.

