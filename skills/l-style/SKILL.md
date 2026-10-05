---
name: l-style
description: "How Luca wants all code, prose, commits and docs written: the always-on core (philosophy, naming, code style, comments, the Writing hard rules) plus an index of the on-demand l-style-* parts. Load before writing anything in Luca's name."
---

# l-style (core)

Load this core before writing ANYTHING in my name: code, commits, docs,
latex, math, and any message sent as me (gh/issue/PR/MR comments, emails,
chat). If a task produces text or code attributed to me, this applies. The
core is small on purpose and always loaded; the heavier rules live in
on-demand parts, loaded per task from the index below.

Scope: this guide governs my own repos and new code. In a repo I don't own, or one with
established conventions (naming, branching, infrastructure, commit format), match that repo;
where the two conflict, the repo wins. The Writing hard rules still hold for text sent as me.

Scale to the artifact. Naming, error handling, ASCII, comment and commit rules always apply.
Project machinery (entry point, devenv, CI, generated API reference, simulation, reflection,
observability) applies to repos meant to last, not to one-off scripts or snippets.

## On-demand parts: load the one the task needs

| skill | load it when | covers |
|---|---|---|
| `l-style-architecture` | designing or writing non-trivial code, a module, an API or a data structure | data oriented procedural programming, Tiger Style assertions, architecture, API and header design, memory, robustness and security |
| `l-style-testing` | writing tests, benchmarks, logging, tracing or profiling | the testing order (simulation, formal, fuzz, property), observability and introspection |
| `l-style-tooling` | setting up build/run tooling, environments, infra, git workflow, CI/CD or generated docs | tooling and reproducibility, infrastructure, git, CI/CD, documentation |
| `l-style-latex` | writing LaTeX, mathematics, proofs or Lean formalization | LaTeX project layout, preamble/macros, notation, theorems/proofs/references, math |

The commit-message rules live in `l-style-tooling` (Git); load it before writing a commit.

## Philosophy

- Find the primitives of the problem first: the few irreducible operations and the data they act on. Get those right and features fall out. Get them wrong and nothing above them recovers.
- Execute the core feature well; everything else enhances it. Features must interact predictably, and one that only works in isolation isn't done.
- Complexity comes from the problem or not at all. Power comes from orthogonal primitives that compose, not from a list of special cases.
- Design by workflow. Start from the sequence a person actually performs and make it short. Nothing gets built that isn't on a real workflow.
- Abstractions are earned by two real call sites and a problem they remove.
- Never settle for quick and dirty, and carry no technical debt. If the fix doesn't fit the architecture, change the architecture, but propose it first and do it only when asked; a requested small fix stays small.
- Idle costs nothing. No polling, no eager startup work for facilities not in use, no allocation on paths that don't need it. Facilities that are off compile out or cost nothing.
- Fast by construction: right data structure, no work done twice, no allocation in a loop, no round trip that could be a batch.
- No bullshit. No unasked telemetry, no forced accounts, no dark patterns, no framework tax, no config file required to say hello.
- Developer experience matters as much as user experience. Friction in install, first run or the edit-run loop is a defect.
- Tight feedback loops. The time from a change to knowing whether it worked is measured in seconds: hot reload, incremental builds, the relevant tests on save, errors that name the fix. Every step that waits on a human, a full rebuild or a remote service gets a local fast path. A slow loop is fixed before the next feature, because every later change pays for it.
- Minimize dependencies, CPU, RAM, allocations, syscalls, binary size. Every dependency is a permanent liability, and a proprietary one is priced by someone else.

## Naming

Nyangine style everywhere, adapted to each language's casing but not to its habits. The shape is `subject_verb_object`, most significant part first, so everything about one type sorts together and completion on the type name lists its whole API: `user_get_display_name`, `user_find_by_email`, `user_from_row`, `user_admin_create`, `array_push_back`.

- C: module prefix, `nya_array_push_back`, `gny_entity_box_create`. Types `NYA_Error`, constants `NYA_UPPER_SNAKE`, internals `NYA_INTERNAL`.
- Rust: free functions in the type's module, `user::get_display_name`, `user::from_row`. Inherent methods where the language expects them, ordering still subject-first (`User::find_by_email`, not a free `find_user`). Types `PascalCase`, constants `SCREAMING_SNAKE`.
- TypeScript: `userGetDisplayName`, `userFromRow`. Camel because the language is camel, subject-first because that's the rule.
- Python: `user_get_display_name`, `user_from_row`, straight across.
- Program identifiers are explicit and unabbreviated (LaTeX macros and labels may abbreviate standard math terms), with qualifiers in them: `count_max`. No negations.
- Every quantity carries its unit, because the software runs in reality. With an algebraic type system (Rust, OCaml, Haskell) the unit is the type: `Meters`, `Duration`, `Bytes`, and mixing them fails to compile. With a weaker one (C, C++, Java) the unit is in the name: `timeout_ms`, `size_bytes`, `distance_m`. Never neither.
- One verb vocabulary across every language. Inverse pairs: `create`/`destroy`, `init`/`shutdown`, `start`/`stop`, `begin`/`end`, `open`/`close`, `acquire`/`release`, `lock`/`unlock`, `push`/`pop`, `add`/`remove`, `attach`/`detach`, `enable`/`disable`, `bind`/`unbind`, `subscribe`/`unsubscribe`, `save`/`load`, `serialize`/`deserialize`, `encode`/`decode`. Unpaired verbs: `get`, `set`, `find`, `contains`, `from`, `to`, `parse`, `render`. Never two words for one operation, never a language-specific synonym.
- Every inverse verb ships with its partner, same header, adjacent, same visibility. A `_create` without a `_destroy` is unfinished even when there's nothing to undo yet. Write the empty one, so callers can pair their code and the day it does something isn't a breaking change.
  - Pairs match exactly in subject and qualifiers: `arena_temp_create` pairs with `arena_temp_destroy`, not with `arena_free`. Round trips (`save`/`load`, `serialize`/`deserialize`, `encode`/`decode`) get a property test.
  - Teardown accepts every value setup can return, including the failure or `_NONE` value, and does nothing for it. Destroying a stale handle (a double destroy) is a programmer error and asserted.
  - Scope-based cleanup (`defer`, `Drop`, `with`) sits on top of the pair, not in place of it.
- Casing, module system and visibility keywords are the language's. Ordering and vocabulary are mine, and in my own code no framework convention overrides them.
- No magic numbers, no magic strings: every literal that isn't `0`, `1` or an obvious index is a named constant (full rule in Code Style). The same number in two places is one constant used twice.

## Code Style

- Code reads like natural language. Names describe purpose; nobody should need the body to know what a function does.
- Banner comments, in the language's comment syntax, separate sections, and lower-level functions come before the higher-level ones using them.

```c
/*
 * -----------------------------------------------------------------------------
 * SECTION NAME
 * -----------------------------------------------------------------------------
 */
```

Usual sections, lowest level first: `CONSTANTS`, `TYPES`, `INTERNAL`, `LIFETIME`, `FUNCTIONS`.

- Inline comments minimal, informative, lowercase. Doc comments (`/** */`, `///`) are prose and keep normal capitalization.
- Inline comments are one line, maximally. A why that needs a paragraph is in-code documentation (below) if it must stay visible, otherwise the commit message; never a stack of comment lines.
- In-code documentation is not a comment and runs as long as it needs: API docs (doc comments `///`, `/** */`, docstrings, the file/module header block described in `l-style-architecture`, API Design) the note on a workaround for a dependency bug, the derivation of a named constant, and a rejected alternative that still constrains the code (in the module header block). It documents the contract or the constraint, not the debugging history.
- Use only ASCII symbols in code. No Unicode box-drawing, block, or geometric glyphs as decoration (`# _ | [ ] < > / \ + - = : . * o x` instead of box-drawing lines, shade blocks, filled squares, circles, crosses and triangles). Real content (a UI's own icon font glyphs, a language's operators, test data that must contain the character) is exempt; the rule is about decoration.
- Comment the why, never the what. Anything that looks wrong, arbitrary or removable, and isn't, carries its reason next to it:
  - Workarounds for bugs in a dependency, the compiler, the OS or the hardware. Name the thing, the version range, the issue link, what happens without the workaround, and what would let it be deleted; this is documentation, so it takes the lines it needs.
  - Edge cases the code exists to handle, with the input that produces them. "the seventh crate in a tick got no sound" beats "handle edge case".
  - Ordering and timing constraints: why this call comes before that one, what breaks if it moves.
  - Rejected alternatives: a one-line pointer at the point they'd be reintroduced, the reasoning in the module header block, so nobody spends an afternoon rediscovering why the obvious version doesn't work.
  - Deliberate deviations from the rules in this document.
- A why-comment is load-bearing. When its reason expires, delete the comment and the code it justified in the same commit.
- No magic numbers, no magic strings. Every literal that isn't `0`, `1` or an obvious index is a named constant, defined once next to what it governs, with its derivation as in-code documentation: what it was measured against, what it trades off, what breaks above and below it.
  - The same number in two places is one constant used twice: a limit, its buffer size and its assert all read from one definition. Units follow the units rule; in C the constant carries them in its name, `TIMEOUT_MS`, `SIZE_BYTES`, `COUNT_MAX`.
  - Same for strings: paths, keys, routes, env names, file magic, so a rename is one edit.
  - Nothing up my sleeve. Every constant is derivable from something, especially in security code: seeds, IVs and table constants come with where they came from. A number nobody can account for is either a bug or a backdoor.
- Formatting is tool-enforced and never argued about: wide columns (120 to 150), aligned consecutive assignments, declarations and macros, block indent, no bin-packing of arguments, regrouped sorted includes (clang-format; other languages use their standard formatter at the same width).
- Zero warnings, zero lint findings, zero errors. Lint sets are maximal (`bugprone-*`, `cert-*`, `clang-analyzer-*`, `concurrency-*`, `performance-*`, `readability-*`, clippy pedantic). A disabled check needs a comment saying why it doesn't apply.

## Writing

How I write prose: essays, docs, commit and PR bodies, issue and gh comments, emails, chat. Skill files and repo docs (README, AGENTS.md, specs, TODO.md) count as docs, so the hard rules below apply to them.

Hard rules, no exceptions:

- ASCII punctuation and symbols only: no smart or typographic quotes, no unicode dashes, arrows or bullets. Straight `"` and `'`. The letters of the language (ä, ö, ü, ß) are allowed.
- No em dashes. No en dashes. Use `to` / `bis` for ranges in prose; code keeps its own range syntax.
- Never use `" - "` (space hyphen space) as a sentence connector. Use a colon, a period, or restructure.
- Terse, for everything outside the long-form list below. No filler, no throat-clearing, no padding. No comment essays. Say the thing and stop.
- gh, PR and issue comments are one or two short lines. The root-cause story goes in the commit or `TODO.md`, not the comment.
- Preserve the language being written in. Most of my prose is German, some English. Write in the language of the context or request and never mix the two in one piece. Code, identifiers, comments and commits are English; only prose for people follows the context language.

Style, inferred from real work. Long-form prose only (essays, reports, applications, standalone explanatory articles; not README, AGENTS.md, specs, TODO.md, skill files or API docs); commits, PR and issue bodies, gh comments and emails follow the hard rules alone:

- Open by naming the common view, the problem, or the general setting, then pivot to the actual point with `jedoch` / `however` / `allerdings`. State the question the piece answers early.
- Drive the text with a direct question, then answer it. "Nun stellt sich die Frage:", "Does there exist ...? And indeed, this can be answered."
- Signpost and walk the reader through in order. "Beginnen wir mit ...", "We will now ...", "In this chapter we look at ...", "As an example, consider ...". Sequential or chronological, one step at a time.
- Argue from concrete evidence: named dates, figures, quantities, line numbers, quoted phrases, named devices. Never a vague claim where a specific fact fits.
- Mix rhythm. Long hypotactic analytical sentences carry the argument, then a very short declarative lands it. "This is a disappointing result." "Man weiß es nicht." Do not make every sentence the same length.
- Carry the logic on explicit connectives: `somit`, `folglich`, `jedoch`, `hence`, `thus`, `furthermore`, `however`, `therefore`.
- Match register to context. Formal and precise for applications, reports and academic prose. Dry, first-person, self-aware wit is allowed in reflective pieces, never in formal ones.
- First person is fine and owns the claim: "ich", "we", "meiner Meinung nach", "I am certain that". Use `we` to walk the reader through a derivation.
- Close with a crisp verdict or the single point, not a recap of everything said.
