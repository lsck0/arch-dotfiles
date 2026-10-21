---
name: l-style
description: "How Luca wants all code, prose, commits and docs written: the always-on core (philosophy, naming, code style, comments, the Writing hard rules, no AI slop) plus an index of the on-demand l-style-* parts. Load before writing anything in Luca's name."
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
- Native over bolt-on. Solve each thing with the framework's own mechanism, not a wrapper or a polling loop that reimplements what the tool already provides. A solution that fights its tool is the wrong solution.
- Sane over default. Being the convention is not a reason on its own: when a better-designed tool exists and fits, use it. Scripting is nushell (typed, structured data, real control flow), not bash or python; bash only where nothing else can run (an install ISO, an initramfs, a tool that sources sh). Config is the app's own language (lua where the app takes lua). Native over bolt-on still holds: the saner tool is used directly, never wrapped around the default.
- One extension pattern, same for a human and an agent. A new capability is a file that follows the established convention, discoverable from the project's index; adding the file is the whole change, nothing central edits to register it.
- Design by workflow. Start from the sequence a person actually performs and make it short. Nothing gets built that isn't on a real workflow.
- Abstractions are earned by three or four real call sites and a problem they remove. Two similar pieces of code are not yet a pattern; extracting them early guesses the shape wrong.
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
- nushell: kebab-case commands and variables, subject first: `user-get-display-name`, `file-update`; subcommands as `def "main user get"`.
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
- A file reads bottom-up: constants, types, internal helpers, lifetime, then the functions using them, lower-level
  before higher-level. The order shows the sections; no banner comments.
- Comments are three kinds, nothing else:
  - A header comment at the top of a file or module, where its purpose or contract isn't obvious from the name.
  - Doc comments in the language's own documentation format, the one its generator reads (Doxygen `/** */` in C and
    C++, `///` and `//!` rustdoc in Rust, Javadoc in Java, TSDoc/JSDoc in TypeScript and JavaScript, docstrings in
    Python, `#` above a `def` in nushell, which is its `--help`), on the public API and on an internal declaration whose
    contract isn't obvious from the signature. Prose with normal capitalization; one that repeats the name is deleted.
  - Otherwise only where it is exceptionally unclear why the code exists: a workaround for someone else's bug, an
    ordering that breaks when moved, a check that looks removable and isn't. One line, lowercase, naming the reason.
- Never a comment that restates the code, narrates the steps, labels a section, or tells the story of the change (that
  is the commit message). No stacks of comment lines. When its reason expires, delete the comment with the code.
- Use only ASCII symbols in code. No Unicode box-drawing, block, or geometric glyphs as decoration (`# _ | [ ] < > / \ + - = : . * o x` instead of box-drawing lines, shade blocks, filled squares, circles, crosses and triangles). Real content (a UI's own icon font glyphs, a language's operators, test data that must contain the character) is exempt; the rule is about decoration.
- No magic numbers, no magic strings. Every literal that isn't `0`, `1` or an obvious index is a named constant, defined once next to what it governs; its name says what it is, and a comment gives its derivation only where that is exceptionally unclear.
  - The same number in two places is one constant used twice: a limit, its buffer size and its assert all read from one definition. Units follow the units rule; in C the constant carries them in its name, `TIMEOUT_MS`, `SIZE_BYTES`, `COUNT_MAX`.
  - Same for strings: paths, keys, routes, env names, file magic, so a rename is one edit.
  - Nothing up my sleeve. Every constant is derivable from something, especially in security code: seeds, IVs and table constants come with where they came from. A number nobody can account for is either a bug or a backdoor.
- Formatting is tool-enforced and never argued about: wide columns (120 to 150), aligned consecutive assignments, declarations and macros, block indent, no bin-packing of arguments, regrouped sorted includes (clang-format; other languages use their standard formatter at the same width).
- Zero warnings, zero lint findings, zero errors. Lint sets are maximal (`bugprone-*`, `cert-*`, `clang-analyzer-*`, `concurrency-*`, `performance-*`, `readability-*`, clippy pedantic). A disabled check needs a comment saying why it doesn't apply.

## No AI slop

Everything in my name reads like a careful human wrote it. The test for every line, in code and prose alike: would someone who cared, and had to type it by hand, have written this? If not, delete it.

- No restating, narrating or summarizing comments, no comment essays, no "Step 1:" walkthroughs, no section banners.
- No dead or defensive code nobody asked for: checks that cannot trigger, fallbacks for states that cannot exist, unused parameters, options and flags no caller passes, wrappers that only forward.
- No duplicated helpers. Before writing a function, find the existing one; one implementation per concern.
- No generic names (`data`, `result`, `info`, `helper`, `manager`, `utils`, `handle_stuff`) and no names that inflate (`ultimate`, `enhanced`, `smart`, `advanced`).
- No hype vocabulary in prose: robust, seamless, leverage, comprehensive, cutting-edge, powerful, elevate, delve, crucial, ensure (as filler), "it's worth noting", "in summary", "let's dive in". No hedging stacks, no restating the question, no closing recap.
- No decoration: emoji, unicode arrows and bullets, bold scattered through sentences, exclamation marks, headers on a five-line file.
- No sci-fi or marketing labels in a UI ("HUD READOUT", "FLUX TELEMETRY"): name the thing plainly, in the casing the rest of the UI uses.
- No AI attribution in the artifact: no "generated by", no co-author trailers, no assistant voice ("I've updated", "Here's").
- Output follows the repo, not the model's habits: its formatter, its line width, its helper library, its comment density.

## Writing

How I write prose: essays, docs, commit and PR bodies, issue and gh comments, emails, chat. Skill files and repo docs (README, AGENTS.md, specs, TODO.md) count as docs, so the hard rules below apply to them.

Hard rules, no exceptions:

- ASCII punctuation and symbols only: no smart or typographic quotes, no unicode dashes, arrows or bullets. Straight `"` and `'`. The letters of the language (ä, ö, ü, ß) are allowed.
- No em dashes. No en dashes. Use `to` / `bis` for ranges in prose; code keeps its own range syntax.
- Never use `" - "` (space hyphen space) as a sentence connector. Use a colon, a period, or restructure.
- Terse, for everything outside the long-form list below. No filler, no throat-clearing, no padding. Say the thing and stop.
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
