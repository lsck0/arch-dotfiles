---
name: l-personas
description: "Persona system: domain-specific instructions layered onto an agent."
---

# l-personas

A persona is a `l-persona-<name>` skill: a focused set of instructions for
one domain (research, design, implementation, review, ...) that narrows
how an agent does a task, not a separate agent.

Before starting non-trivial work, check if a persona matches the domain
and load it. Discover the current set dynamically instead of hardcoding
a list — a new persona shows up with zero changes elsewhere:

```python
personas = [s for s in skills_list()["skills"] if s["name"].startswith("l-persona-")]
```

## Current personas

| skill                                 | description                                                        |
| ------------------------------------- | ------------------------------------------------------------------- |
| `l-persona-research-codebase`         | Search the codebase for patterns, conventions, API boundaries.    |
| `l-persona-research-literature`       | Search prior art: papers, algorithms, how others solved this.     |
| `l-persona-research-customers`        | Mine forums/social for user needs, complaints, and requests.      |
| `l-persona-research-market`           | Survey competitors, alternatives, patents, and licensing.         |
| `l-persona-design-architecture`       | Design high-level architecture, data flow, and infrastructure.    |
| `l-persona-design-api`                | Design one module's API: functions, data structures, contracts.   |
| `l-persona-design-uiux`               | Design UI flows, interaction, accessibility, and i18n.            |
| `l-persona-programmer`                | Implement tickets: write the actual code.                         |
| `l-persona-investigator`              | Root-cause bugs and incidents: logs, commits, stack traces.       |
| `l-persona-pentester`                 | Blackbox pentest: attack the running system, find real breaks.    |
| `l-persona-auditor-security`          | Passive security audit: code, config, CI/CD, dependencies.        |
| `l-persona-auditor-performance`       | Audit code for wasted throughput: data structures, cache, allocs. |
| `l-persona-devops`                    | CI/CD, infra, deployment, and observability.                      |
| `l-persona-orchestrator`              | Spawn and direct other agents; the authority over the run.        |
| `l-persona-orchestrator-task-planner` | Turn a raw ask into an ordered set of tickets.                    |
| `l-persona-tester`                    | Write tests: unit, e2e, fuzz, property, formal verification.      |
| `l-persona-reviewer`                  | Independent review: conventions, style, and correctness.          |

Not exhaustive, the discovery snippet above is the source of truth.
