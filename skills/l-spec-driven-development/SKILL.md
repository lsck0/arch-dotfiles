---
name: l-spec-driven-development
description: "Agent programming workflow."
---

# l-spec-driven-development

Research, then design, then spec, then human approval, then build.
Load for real non-trivial features, bugs or investigations.

## Steps (drop what a small task doesn't need, keep the order)

0. Namespace: `specs/spec-<number>-<feature-name>/`, or the project's own equivalent.
1. Research -> `RESEARCH.md` (code, logs, web/market/lit search).
2. Design -> `DESIGN.md` (architecture/API/data model/UI). Ask the human on anything that isn't yours to decide.
3. Review: fresh context, checked against the project's own guidelines.
4. Spec -> `SPEC.md`: TLDR, concepts, API signatures, data structures, algorithms, integration points. Enough that an implementer never has to ask.
5. Human review, iterate to explicit approval.
6. Roadmap -> `ROADMAP.md`: phases/tickets, each traceable to a spec section.
7. Implementation: work the roadmap. Hold every ticket/phase to the codebase's actual standards of correctness.

## Parallelism and model choice

An agent acting as an orchestrator (`l-multi-agent-mode`/ `l-multi-agent-task-mode`) should:

- size subagent count and model strength to the stage, small/cheap models for research, strong models for design and spec.
- start every step with a fresh context.
- communicate through markdown files in the spec directory.
