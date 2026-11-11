---
name: l-pottery-development
description: "Pottery (clay) workflow: throw every feature on at once in a rough pass, then make it compile, then refine pass after pass (trim, name, test, optimize) until it holds. Load when Luca says throw it all on, clay, pottery, breadth first, or for a batch of features on a greenfield or pre-MVP project he owns. One task at a time instead: l-incremental-development; a specced, phased change: l-spec-driven-development."
---

# l-pottery-development

Clay on a potter's wheel: the whole shape goes on first, rough, then it is shaped by repetition. Quality comes from the
refinement passes, not from each first stroke being final. Per-item build, review and fix cycles are slow and burn
compute; here breadth comes first and the polish comes after.

The three ways of working, pick by the ask:

| way | shape | skill |
|---|---|---|
| spec-driven | research, a phased spec, each phase a revertible PR | `l-spec-driven-development` |
| pottery | throw everything on, then refine and refine | this skill |
| incremental | one task at a time, as the developer at the keyboard | `l-incremental-development` |

## When

- A greenfield or pre-MVP project, or a batch of features on a project Luca owns, where nothing has to keep running
  between steps.
- Luca asks for breadth first: "throw all features on it", "clay", "then refine, optimize, test".
- A spec is optional. With one, this is `l-spec-driven-development`'s whole-project shape; without one, the feature list
  in the ask (or `TODO.md`) is the plan.

Once the project has something worth keeping running, or other people depend on it, it graduates to the incremental
shape and stays there.

## The passes

1. **Throw.** Every feature gets a rough first implementation in one broad pass. With subagents: several writers in
   parallel, each in its own worktree, each only writing code, no builds, no tests, no review. Each writer gets the
   feature, the files it owns and the l-style rules it must follow, nothing more. Overlapping files go to one writer.
2. **Center.** One integration round in the main tree, serial, one build at a time: merge the worktrees, make it compile,
   make the targeted tests pass. Fix only what blocks the build or a test; leave the rest for the refinement passes.
3. **Refine**, as many rounds as it takes, each a pass over the whole thing with one lens:
   - trim: dead code, duplicated helpers, forwarding wrappers, comment spam (`l-style`, No AI slop);
   - naming: one coherent system, siblings across layers mirrored (`l-style`, Naming);
   - correctness: tests per `l-style-testing`, then review (`l-persona-reviewer`);
   - performance: benchmark, then optimize the measured hot paths (`l-persona-auditor-performance`).
   Repeat until a full round changes nothing that matters. Then a single strict-check pass (lint, full tests, sanitizer
   build) closes it.

Reviews and polish per item are not part of the throw; asking for them there defeats the method.

## Rules

- Throwing writers fan out; anything that builds stays inside the parallelism budget of `l-spec-driven-development`
  (machine first: read-only and writing agents may go wider only while nothing builds).
- Never build in the main checkout while writers merge into it, and never under an app Luca is running from it: builds
  go in a worktree.
- History during the throw may be messy (`l-style-tooling`, Git, pre-MVP exemption); the repo's commit rules still hold
  (arch-dotfiles and homelab: no agent commits, Luca's sync commits).
- Where the work stands goes in the repo's `TODO.md`, not agent memory (`l-auto-memory`).
- A gap in a dependency another session owns goes to that session with the exact need; stub that piece and throw on.
