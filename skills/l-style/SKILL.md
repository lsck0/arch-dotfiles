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

Scope: this guide governs my own repos and new code, and it governs in full the moment I take over a
whole project or a large part of one, however old the code is: a takeover means the full standard now
applies and the code is brought to it, incrementally on a live system (`l-spec-driven-development`'s
incremental shape), not by a big-bang rewrite. The one exception is a minor change in an existing, mature codebase I do not own:
there, match the repo's established conventions (naming, branching, infrastructure, commit format), and
where the two conflict the repo wins, so a small fix stays small and in the local idiom. A "minor change"
is a bounded fix or addition that leaves the architecture as it was; once I am reshaping modules, owning
subsystems or setting the direction, the exception is over and this guide applies. The Writing hard rules
hold for any text sent as me, no exception.

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
| `l-style-unreal` | building a component inside a large third-party engine like Unreal | C++ over Blueprint, an own subsystem table, determinism, build and test policy |

The commit-message rules live in `l-style-tooling` (Git); load it before writing a commit. For work in
nyangine, my C engine and the reference implementation of this guide, load `l-engine` for orientation.

The style skills carry general principles and illustrate them with my own naming, so a reader can apply them
to any project; they do not describe or leak a private project. Only the engine skill names the engine, and
the operational skills (`l-dotfiles`, `l-homelab`) name the systems they drive, because that is their job.

## Philosophy

Software is a craft, and the work carries a craftsman's name. The bar is quality that lasts: correct, fast, small,
and still clear to the next person who opens it. The aim every time is the best possible software, never the quickest
thing that passes; shortcuts that trade the architecture for a deadline are not on the table.

When two of these pull against each other, the order that breaks the tie is: security, privacy, stability,
performance, then lines of code. Security and privacy are defaults, not features, and never traded down.
Fewer lines is the last tiebreaker, never bought at the cost of correctness, safety or clarity.

- Find the primitives of the problem first: the few irreducible operations and the data they act on. Get those right and features fall out. Get them wrong and nothing above them recovers.
- Execute the core feature well; everything else enhances it. Features must interact predictably, and one that only works in isolation isn't done. A feature is finished only once something real exercises it: a caller in the product, an example, a test. A change to a user interface is finished only once someone has looked at it on screen.
- Complexity comes from the problem or not at all. Power comes from orthogonal primitives that compose, not from a list of special cases. Hard problems are allowed to need hard software and competent people; the response to difficulty is a better primitive, never a layer that hides it.
- Expose power through one stable, language-neutral interface, not through bindings hand-written for one language. A flat ABI or a protocol that any language can call is the product; a scripting language is then just one consumer of it, and its bindings are generated from the interface, not maintained by hand. Lua is a consumer, not the design.
- Deterministic by default. Same input, same output. Everything nondeterministic sits behind an interface the test harness controls: time is injected, randomness is seeded, I/O is mocked, iteration order is fixed, so any run replays exactly. This is what makes simulation testing, reproducible builds and honest debugging possible, and it is far cheaper designed in than bolted on, so it is designed in from the start.
- One way to do a thing. One format per kind of asset, one API per job, one vocabulary across the codebase. A second way to do the same thing is a defect, not a convenience.
- Lines of code and dependencies are a cost paid forever, so spend them in proportion to the project. The best code is the least code that solves the real problem well: no speculative generality, no abstraction without its three or four call sites, no framework stood up for a script, no subsystem split out before a second caller needs it. Quality and "no debt" mean fit, not grandeur: over-engineering and architecture for a problem you do not have is itself the debt. Match the weight of the design to the weight of the problem, and no heavier.
- Native over bolt-on. Solve each thing with the framework's own mechanism, not a wrapper or a polling loop that reimplements what the tool already provides. A solution that fights its tool is the wrong solution.
- Sane over default. Being the convention is not a reason on its own: when a better-designed tool exists and fits, use it. Scripting is nushell (typed, structured data, real control flow), not bash or python; bash only where nothing else can run (an install ISO, an initramfs, a tool that sources sh). Config is the app's own language (lua where the app takes lua). Native over bolt-on still holds: the saner tool is used directly, never wrapped around the default.
- One extension pattern, same for a human and an agent. A new capability is a file that follows the established convention, discoverable from the project's index; adding the file is the whole change, nothing central edits to register it.
- Design by workflow, and know whose workflow. Name the people the software is for and the sequences they actually perform, then make those sequences short and build nothing that is not on one. The audience and its workflows come before the feature list, the data model and the API; a design that cannot name its user is not started yet.
- Let the machine catch mistakes so people do not have to. Everything is type-safe: illegal states are unrepresentable, units and constraints live in the type, and the API makes the right call the easy one and the wrong call fail to compile. Tooling is everywhere and autocomplete lists a type's whole surface (the naming shape serves this). The defenses form a ladder, each catching what the last let through: compile-time checks, then assertions, then tests, deterministic simulation and fuzzing, then benchmarks for regressions. The aim is that nothing reaches a user that these could have caught.
- For the rare escape that reaches production, diagnosis is built in, never improvised after the fact. One crash funnel assembles the whole picture (the live scope stack, the error's propagation trace, the stack trace, the recent log lines, the build metadata and machine details) into a single report, offered to the user behind one plain action that sends it to the developer: one button, or zero where it can be automatic (a frontend reporting on its own). Everything needed to reproduce is already attached. Reporting always respects the user's privacy: it is opt-in or opt-out as the circumstance demands, the user stays anonymous, and nothing identifying leaves the machine without consent. That consent is the whole reason it is a button and not a silent upload.
- Abstractions are earned by three or four real call sites and a problem they remove. Two similar pieces of code are not yet a pattern; extracting them early guesses the shape wrong.
- Never settle for quick and dirty, and carry no technical debt. Debt is not "cleaned up later"; it is not taken on. If the fix doesn't fit the architecture, change the architecture, but propose it first and do it only when asked; a requested small fix stays small.
- Power over hand-holding. The audience is competent people who know what they are doing; never trade capability for beginner-friendliness, never dumb an interface down to a lower common denominator. User-facing copy (CLI, bootstrap, prompts, errors) is terse and direct: ask the question plainly, state a consequence only when it is severe or irreversible, and never explain what the reader already knows.
- Idle costs nothing. No polling, no eager startup work for facilities not in use, no allocation on paths that don't need it. Facilities that are off compile out or cost nothing.
- Fast by construction: right data structure, no work done twice, no allocation in a loop, no round trip that could be a batch.
- Name the assumptions before building, then design for the real numbers, not the demo. Write down what the code assumes about its environment and its input, and check each one: the screen or terminal size it must fit (an 80x24 tty, a small laptop, a vertical monitor), how many items actually occur at the high end (thirty Wi-Fi networks in a dense block, a day with twenty events, a thousand tasks) and whether they fit, the longest string that can arrive, the memory and whether anything grows unbounded with input or time, and what happens at zero and at the maximum. A list that can exceed its viewport scrolls and is bounded with the bound stated; a widget says how many it shows and degrades instead of overflowing. An assumption left unstated is the bug report you have not read yet.
- No bullshit. No unasked telemetry, no forced accounts, no dark patterns, no framework tax, no config file required to say hello.
- The user is sovereign and is treated with respect. Give them full power and the final decision rather than babysit or belittle them. Never pull what Windows pulls: no forced updates, no nagging, no decision made for the user that silently cannot be undone, no feature that serves the vendor against the user. Every consequential action is the user's to take, to defer, or to refuse, and the defaults respect that freedom.
- Developer experience matters as much as user experience. Friction in install, first run or the edit-run loop is a defect.
- Tight feedback loops. The time from a change to knowing whether it worked is measured in seconds: hot reload, incremental builds, the relevant tests on save, errors that name the fix. Every step that waits on a human, a full rebuild or a remote service gets a local fast path. A slow loop is fixed before the next feature, because every later change pays for it.
- Minimize dependencies, CPU, RAM, allocations, syscalls, binary size. Every dependency is a permanent liability, and a proprietary one is priced by someone else.
- Be a good tenant of the machine. A program bounds its own footprint and leaves the host usable for everything else: it does not seize all the RAM, cores or file handles just because they exist. Even on a large machine there is no reason to take 60 GB of memory so nothing else can run. Size the caps (memory pools, thread counts, cache and queue sizes, parallelism) to a sane share of the machine, make them configurable, and degrade or wait rather than exhausting the system. This holds for an agent running work too: a heavy build or test goes through a low-priority scope (`fence`, see `l-persona-programmer`) and a bounded worker count, so it never starves the desktop, a game, or another session.
- Software is a marathon, not a sprint, and the fundamentals are what carry it: project structure, tooling, tests, and runtime diagnostics (scoped timings, tracing, telemetry, benchmarks) go in early, before and alongside features, not after a problem appears. They are not overhead; they are the machine that keeps every later change fast and safe, and a project without them rots however clever its features are. Keep them in proportion, though: they serve the code, they are not the project. A repo that is mostly tooling and benchmarks around a sliver of real functionality got the ratio wrong as surely as one with none.

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
  - Teardown accepts every value setup can return, including the failure value and the type's invalid or absent value (for a handle that is the zero slot; see `l-style-architecture`), and does nothing for it. Destroying a stale handle (a double destroy) is a programmer error and asserted.
  - Scope-based cleanup (`defer`, `Drop`, `with`) sits on top of the pair, not in place of it.
- Casing, module system and visibility keywords are the language's. Ordering and vocabulary are mine, and in my own code no framework convention overrides them.
- No magic numbers, no magic strings: every literal that isn't `0`, `1` or an obvious index is a named constant (full rule in Code Style). The same number in two places is one constant used twice.

## Code Style

Every line is written once and read many times, by a human who maintains it later. Aesthetics are load-bearing, not
decoration: spacing, alignment, sorting and above all naming are the interface to the code. The clarity goes into the
name and the structure, so that almost nothing is left for a comment to say. This effort is cheaper than every reading
that follows.

- Code reads like natural language. Names describe purpose; nobody should need the body to know what a function does.
  When something is unclear, the first fix is a better name or a better structure, not a comment.
- A file reads bottom-up: constants, types, internal helpers, lifetime, then the functions using them, lower-level
  before higher-level.
- Encapsulate at the module level, not the declaration level (`l-style-architecture`, API Design). A file separates
  its sections with a banner, and that banner is the only comment allowed to label anything:
  - A public interface (a header) splits into public API and private API; an implementation file into the sections of
    the bottom-up order it actually has (constants, types, internal implementation, lifetime, public implementation).
    Use only the dividers a file needs; a short file needs none.
  - The banner is one line: an ASCII rule carrying the section name, in the file's established style. Never narrative,
    never a label on a single declaration, never a phase of the code.
- Comments, fewer always better, in order of preference:
  - A file or module header doc comment: what this is, its purpose, and the core of how to use it. Length scales to
    need, one line to a short paragraph, and no further. No essays.
  - A doc comment on a public declaration only when its name and full signature do not already say what it does, what
    it needs, what it returns and how it fails. A self-explaining signature gets none; one that repeats the name is
    deleted. Written in the language's own doc format (Doxygen `/** */` in C and C++, `///` and `//!` rustdoc in Rust,
    Javadoc in Java, TSDoc/JSDoc in TypeScript and JavaScript, docstrings in Python, `#` above a `def` in nushell).
  - A doc comment on an internal declaration, a struct field or a variable only in the exceptionally rare case where
    the name cannot be made clear and renaming or restructuring is not an option: a vendor-library bug, a hardware
    quirk, an ordering that breaks when moved, a check that looks removable and isn't. One line, naming the reason.
  - Inside a function body, a `//` comment only to mark the rough phases of a long or complicated function (`// setup`).
    Prefer a profiling scope over the comment where the project has one (`nya_scope("setup")`, `perf_time_this_scope`),
    so the phase label becomes runtime debug information instead of dead text. A one or two line step gets nothing; a
    twenty-line step is its own function, or earns one phase marker.
- Never a comment that restates the code, narrates a step (`// get user data`), tells the story of the change (that is
  the commit message), or stacks several lines. When a reason expires, delete the comment with the code.
- Use only ASCII symbols in code. No Unicode box-drawing, block, or geometric glyphs as decoration (`# _ | [ ] < > / \ + - = : . * o x` instead of box-drawing lines, shade blocks, filled squares, circles, crosses and triangles). Real content (a UI's own icon font glyphs, a language's operators, test data that must contain the character) is exempt; the rule is about decoration.
- No magic numbers, no magic strings. Every literal that isn't `0`, `1` or an obvious index is a named constant, defined once next to what it governs; its name says what it is, and a comment gives its derivation only where that is exceptionally unclear.
  - The same number in two places is one constant used twice: a limit, its buffer size and its assert all read from one definition. Units follow the units rule; in C the constant carries them in its name, `TIMEOUT_MS`, `SIZE_BYTES`, `COUNT_MAX`.
  - Same for strings: paths, keys, routes, env names, file magic, so a rename is one edit.
  - Nothing up my sleeve. Every constant is derivable from something, especially in security code: seeds, IVs and table constants come with where they came from. A number nobody can account for is either a bug or a backdoor.
- Formatting is tool-enforced and never argued about: wide columns (120 to 150), aligned consecutive assignments, declarations and macros, block indent, no bin-packing of arguments, regrouped sorted includes (clang-format; other languages use their standard formatter at the same width).
- Zero warnings, zero lint findings, zero errors. Lint sets are maximal (`bugprone-*`, `cert-*`, `clang-analyzer-*`, `concurrency-*`, `performance-*`, `readability-*`, clippy pedantic). A disabled check needs a comment saying why it doesn't apply.

## No AI slop

Everything in my name reads like a careful human wrote it. The test for every line, in code and prose alike: would someone who cared, and had to type it by hand, have written this? If not, delete it.

- No restating, narrating or summarizing comments, no comment essays, no "Step 1:" walkthroughs. The only banner allowed is the fixed structural divider of Code Style (public API, private API, the bottom-up implementation sections); never a banner that narrates or labels a single declaration.
- No dead or defensive code nobody asked for: checks that cannot trigger, fallbacks for states that cannot exist, unused parameters, options and flags no caller passes, wrappers that only forward.
- No duplicated helpers. Before writing a function, find the existing one; one implementation per concern.
- No generic names (`data`, `result`, `info`, `helper`, `manager`, `utils`, `handle_stuff`) and no names that inflate (`ultimate`, `enhanced`, `smart`, `advanced`).
- No hype vocabulary in prose: robust, seamless, leverage, comprehensive, cutting-edge, powerful, elevate, delve, crucial, ensure (as filler), "it's worth noting", "in summary", "let's dive in". No hedging stacks, no restating the question, no closing recap.
- No decoration: emoji, ASCII emoticons or kaomoji (`:)`, `\o/`), emote spam, unicode arrows and bullets, bold scattered through sentences, exclamation marks, headers on a five-line file. The voice is my own, a human writing plainly, never an assistant performing enthusiasm.
- No sci-fi or marketing labels in a UI ("HUD READOUT", "FLUX TELEMETRY"): name the thing plainly, in the casing the rest of the UI uses.
- Error and crash copy is factual, terse and respectful: state what happened and the one action to take, nothing more. No apologetic filler ("Oops, something went wrong, we're not sure what, we'll have to restart"), no fake cheer, no blame on the user. A crash dialog names the failure and offers the send-report or restart action; it does not chatter.
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
- Correct standard German (neue Rechtschreibung): comma before an infinitive group with `um`/`ohne`/`statt ... zu`, `dass` vs `das`, compound nouns closed (`Softwareprojekt`, not `Software Projekt`). My own drafts contain typos and split compounds; do not reproduce them.

Style, inferred from real work. The reference voice is mature long-form academic writing (a thesis, a seminar handout) for English mathematical prose, and a professional report for German prose; worked exercise solutions for mathematics. Do not take style from recent machine-drafted study notes or exercise write-ups, even my own: those are agent output, not my voice. The rules below are long-form prose only (essays, reports, applications, talks, standalone explanatory articles; not README, AGENTS.md, specs, TODO.md, skill files or API docs); commits, PR and issue bodies, gh comments and emails follow the hard rules alone:

- Open with the plain setting or the problem in one sentence, then the concrete case, then the question the piece answers. The common-view-then-`jedoch` hook is a school-essay device; keep it for essays and opinion pieces only, not reports, abstracts or explanatory text. An abstract may state the result first.
- The colon is the main hinge: a short lead clause, a colon, then the point, the plan or the lesson. "Die Kurzfassung ist:", "Mein Plan ist der Folgende:", "Wichtig ist:", "The problem:". This is now the dominant pivot in my German prose, ahead of `jedoch`.
- One driving question per piece or section, answered at once, not a question every paragraph. "Does there exist ...? And indeed, this can be answered.", then the answer.
- Signpost and walk the reader through in order, announcing each part's purpose plainly. "Beginnen wir mit ...", "In diesem Kapitel ...", "We will now ...", "The reason ... is the following lemma.". Sequential or chronological, one step at a time.
- Argue from concrete evidence: named dates, figures, quantities, line numbers, quoted phrases. Introduce an unfamiliar scale or a new result by comparison to a familiar one (an area or population against a known region; a new formula against a known one). Never a vague claim where a specific fact fits.
- In reports, put arguments, criticisms and requirements in a numbered list, each item a claim then one or two sentences of specific evidence (a count, a date, one anecdote). In mathematical prose the argument runs as prose between the stated results; lists are for cases and enumerated claims only.
- Mix rhythm. Long hypotactic sentences carry the argument, then a very short declarative lands it: "This is a disappointing result.", "Man weiß es nicht.". Do not make every sentence the same length.
- Carry the logic on explicit connectives: `somit`, `folglich`, `jedoch`, `allerdings`, `hence`, `thus`, `therefore`, `however`, `furthermore`, `in particular`. `Unfortunately` / `leider` only for a real limitation.
- Person by language and genre. German reports and reflections are blunt and first-person (`ich`), and may drop a dismissive one-clause aside and cut it off ("Aber das ist ein anderes Thema."). English mathematical prose is neutral: `we` for the walk, `one` for general possibility, `I` only for authorship facts in an abstract or preface; no irony, and no evaluation beyond a one-sentence verdict on a result.
- Humor is dry, self-deprecating and often mathematical (testing a claim on one's own example, rating one's own work), only in reflective or informal pieces, at most once or twice, never in reports, applications, abstracts or mathematics. A single hidden easter egg in a talk is in character; jokes in the body prose are not.
- Close with a crisp verdict or the single point, never a multi-point recap. Expository German ends "Fazit:" plus one sentence; a reflection ends on the single lesson ("Gelernt habe ich vor allem eines: ...") and maybe a short list; a mathematical paper, handout or talk ends on its last result or the references, with no conclusion or outlook section.
