---
name: l-style
description: "How Luca wants all code, prose, commits, docs, latex, and math written, plus design, architecture, infra and git workflow. Load before writing anything in Luca's name."
---

# l-style

My opinions on software, writing, and math.

Load this before writing ANYTHING in my name: code, commits, docs, latex, math,
and any message sent as me (gh/issue/PR/MR comments, emails, chat). If a task
produces text or code attributed to me, this guide applies.

Scope: this guide governs my own repos and new code. In a repo I don't own, or one with
established conventions (naming, branching, infrastructure, commit format), match that repo;
where the two conflict, the repo wins. The Writing hard rules still hold for text sent as me.

Scale to the artifact. Naming, error handling, ASCII, comment and commit rules always apply.
Project machinery (entry point, devenv, CI, generated API reference, simulation, reflection,
observability) applies to repos meant to last, not to one-off scripts or snippets.

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

## Data Oriented Procedural Programming

Plain data plus functions that transform it. Start from the data and let the code follow. SOLID, OOP, inheritance, design patterns and getter/setter ceremony are not considered.

- Structs are data, not objects. No hidden state, no method whose only job is guarding a field, no `this` acting behind the caller's back.
- Design for the real shape and distribution of the data. Numbers first: how many, how big, how often, how skewed, what's hot, what never changes. Real distributions are lopsided, and the structure follows from that rather than from textbook asymptotics.
- Optimize the common case as it actually occurs, handle the tail correctly, assert the impossible. A hash map for four entries is worse than an array.
- Size fixed limits from the real distribution, state the reasoning where the number is defined, fail loudly when exceeded.
- Batch over the many rather than dispatching per item. Layout is a design decision: struct-of-arrays where access wants it, cache-conscious in hot paths, explicit sized types.
- Polymorphism only where needed, and then as a tag, a table or a callback registered by name. Readable, not hidden by the language.

## Tiger Style

Written the way TigerBeetle writes it. Assertions are good and crashing is good, and together they make deterministic simulation testing work: the assertions are the oracle.

- Assert everything, and keep the assertions in production. A release build with assertions compiled out has stopped checking itself at the moment it matters.
- Two assertions per function on average: preconditions in, postconditions out, on both sides of every boundary. The redundancy is the point.
- Negative space programming. Define what must never happen and assert its absence, not only what the happy path produces. The space of wrong states is far bigger than the space of right ones.
  - After an operation, assert everything it had no business touching is untouched: no other slot written, no count drifted, no flag set.
  - Assert the impossible branch rather than deleting it: explicit rejection of the transitions a state machine doesn't allow. C: an asserting `default` on every `switch` and a `_COUNT` bound on every enum. Languages with exhaustive `match` list every variant with no wildcard and add no count variant.
  - Reject by default, permit explicitly: unknown field, opcode, version, route. Types carry it too; if a value can't be negative it isn't an `int`.
- Assert relationships, not just values. Ranges, sums, orderings, sizes and offsets that must agree, a length that must match a count elsewhere.
- Two error kinds, treated oppositely:
  - Programmer error, a violated invariant, is impossible by definition. Assert it and crash immediately, loudly, with the state. Continuing past a broken invariant corrupts data; crashing doesn't.
  - Operating error, malformed input, a full table, a failed allocation, a hostile peer, a lying disk, is expected. Handle it explicitly. After startup it never crashes; at startup, a clean exit that names the problem is the handling.
  - Never confuse them. An assert on something an attacker can trigger is a denial of service; a handled error on a broken invariant is data corruption with extra steps.
- Crash-only. Correctness never depends on `shutdown` running: state is valid after a crash at any point, so recovery gets exercised constantly instead of on the worst day. Restart is fast, correct from any point, and needs no manual step. `shutdown` only releases resources, for tests, embedding and hot reload.
- Everything bounded statically, with the bound written down and asserted: loop iterations, recursion depth (prefer none), queue length, message size, retry count, capacity.
- Functions stay short, 100 lines as the usual limit, with explicit control flow. No hidden allocation, no hidden I/O, no hidden control transfer. Hard to see what a function touches means hard to assert.
  - The limit yields to logical coherence: one big switch over events, opcodes or messages, or a render pass that reads top to bottom, stays one function. Never split a coherent unit just to get under the number.
- Declare variables in the smallest scope, close to use.

## Architecture

- Solve problems with architecture, data flow and data structures. A transform sprinkled across call sites means the data structure is wrong.
- Single source of truth for every piece of data or state. If two places can disagree, they will.
- No duplicated or near-duplicated code. On the second occurrence, extract it.
- A new feature is an addition on existing primitives, not a rewrite of what exists. If it can't be, the missing primitive lands first as its own change.
- Monolith by default, no microservices. A network hop isn't a module boundary, it's a boundary plus latency, partial failure, serialization and a second deploy. Split a process out only for a hard constraint: different runtime, different security boundary, incompatible resource profile. A database, cache or proxy beside the app is a dependency with a socket.
- Subsystems and pipelines are the default shape. Each owns its data and has an explicit lifetime (`init` / `tick` / `shutdown`, `tick` only where there is a frame or loop), wired in a known order by one place. Data moves forward through stages, no back-edges, no reaching sideways into another's state.
- Minimal core, extensible features. The core holds only what everyone needs and what can't live outside it. If a feature needs a core change, the core is missing a primitive; add the primitive, not the special case.
- Plugins where extension is expected: stable interface, registration by name, discovery at load, host that knows nothing about them. Adding one requires zero host edits.
- Prefer deferred, batched decisions at a barrier over per-item decisions in callbacks. A callback states a fact, an observer sees the whole frame and decides once, which removes bookkeeping state and makes decisions global instead of first-come-first-served.
- `main` is a composition root: parse arguments, read config, probe the environment, init subsystems in order, run, shut down. No logic, no state of its own. It reads as a list and fits on a screen.
- Configuration lives at the subsystem or API level, never in one global settings object everything reaches into. The module that uses a value defines it, next to its code, with its own defaults and validation, and takes it at `init` or per call. Adding a knob touches one module.
  - Subsystem config comes in once at `init` and holds for the run. Per-call config is an options struct on the call itself, defaulted so the common case passes nothing. A knob that changes between calls belongs in the options struct.
  - Nothing reads another subsystem's config. If two need the same value it's a parameter passed at wiring time.
  - Defaults are in code, complete, good enough to run with no config file at all. File, env and flags override in that order, parsed into the typed struct once at startup. Bad config stops the program before work starts, naming the key, the value and what was expected.
  - Immutable after `init` unless the subsystem supports reload, and then through one function that swaps a validated struct.
- Late binding by name (callback registries, handles) wherever hot reload, serialization or plugins are in play. Raw pointers don't survive a rebuild.
- Group along the architecture's main axis: an ECS engine by kind (`entities/entity_box.c`, `systems/system_camera.c`), a layered backend by layer (`endpoints/endpoint_user.rs`, `services/service_user.rs`). One file owns one thing completely, its prefix mirroring its directory. The tree is documentation.

## API Design

The API is the product. Design it in the header first, implement second. Unpleasant to call means wrong, however good the implementation is.

The signature tells you almost everything: what it does, what it needs, what it gives back, what it can fail with, what it touches and what it costs, before anyone opens the body.

- Parameters are specific enough to be unambiguous: parsed types not raw ones, a handle not an index, a unit-carrying quantity not a bare `f32` (see units under Naming), an options struct past three parameters or whenever two share a type.
- The return type carries absence and failure. A function that can fail says so in its type, never in a comment.
- Ownership, mutation and cost are visible: `const`/`&`/`&mut`, an arena parameter when it allocates, an out-parameter when it writes through (C; elsewhere the value is returned). Where the language can't express thread-safety or blocking, the doc comment states it and an assert enforces it.
- If the signature can't say it, the design is wrong before the code is. A parameter that means different things depending on another parameter is two functions.

### Encapsulation at the API level, not the object level

The boundary is the module's public header: types, functions, guarantees. Layout, algorithm, backing store and third-party library behind it are private and swappable without a caller changing.

- Header declares the contract, implementation file holds the state. Internal functions are `INTERNAL`/`static`/private and never appear in the header.
- Data structs are transparent. Every field public, readable and writable, because data is data. A struct full of private fields is an object pretending to be data.
- Transparency of a public API is a maturity signal. A public struct says the layout is done and is a contract callers may rely on. A public API still in flux stays opaque, a handle plus functions, and opens up once it has settled; its accessors count as crossing a boundary, below. Making a finished struct opaque again is a breaking change.
- Parsed newtypes (Robustness) keep their one field private, so the parser is the only way in.
- Internal state that must not be touched hides behind one opaque pointer, or one clearly marked field on an otherwise transparent struct. Not a private field per secret, not a whole opaque type because two members are delicate. If it's reached for often, it wasn't internal.
- Getters and setters need a reason beyond access. A pass-through accessor is noise. Write one when it computes a derived value, resolves a handle, keeps two fields in sync, notifies on change, or crosses an ABI boundary, and then name it for what it does.
- Callers depend on the interface, never on how it's satisfied. A renderer backend, allocator, database or transport is replaceable behind its existing calls, and every third-party library is wrapped so its types don't leak past the wrapper.
- Pick the implementation at build time by flag or link. If two must coexist, a table of function pointers.
- Prove swappability: simulation tests run against a fake implementation of the same interface.

### Composable

Primitives that combine give more uses than special-case calls do. Something new should be a combination of what exists, not another entry point.

- Shared vocabulary types across modules: one string, one array, one handle, one error, one dynamic value. Conversions happen only at a boundary (wire DTO, storage row, FFI), named `<type>_from_<source>` and `<type>_to_<target>`; between two internal types they are a design smell.
- Functions take and return the same shapes so output feeds input. No adapter layers, no conversions mid-pipeline.
- Combinations are legal by default. Nobody should have to learn which pairs are forbidden.
- Compose behaviour by layering explicit pieces, middleware, stages, observers, not by adding a flag. A boolean parameter that switches behaviour is two functions wearing one name.
- Build the convenience call on top of the low-level one and export both.

### Defends itself

A caller shouldn't be able to hold it wrong without being told immediately.

- Encode the rules in the types: distinct handles instead of raw integers, newtypes instead of bare strings, enums instead of magic values, units per the units rule under Naming, an options struct so two same-typed arguments can't swap. A parameter list of four `int`s is a bug waiting to be reported as a mystery.
- Illegal states unrepresentable rather than validated. Take parsed types as parameters, never the raw form the caller happens to have.
- Assert the contract at the entry point. Out-of-order calls, use before `init`, use after `destroy`, `end` without `begin`, illegal reentrancy, are detected rather than left undefined.
- Handles carry a generation counter, so a stale one is rejected instead of addressing whatever now occupies the slot.
- Return values that matter are marked, so ignoring one is a warning. Bounds are enforced by the API, not by convention.
- Thread-safety, allocation and lifetime rules stated explicitly and asserted where cheap. Silence makes people guess.

### Naming

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

### The rest

- Common case is one call with no ceremony. Config is optional and defaulted.
- Fallible functions return a sum type where the language has them: `Result`/`Option`, a tagged union, one type that holds either the value or the error. C has no built-in sum type, so the default there is an error code (`NYA_Error`) plus out-parameters for values; hot paths may return a small by-value tagged struct (`Maybe`) or a `b8`. Know the size of the error type and state it.
- Errors carry the propagation chain (cheap, always on) and the capture site (expensive, debug only).
- Avoid sentinel values. Absence and failure belong in the type, not in the value's range: `Maybe`/`Option`, a result, a tagged union, an explicit `found` out-parameter. No `-1` for missing, no `0` for none, no empty string for unset, no `NaN` for absent, no magic constant meaning unknown that a later valid input can equal.
  - Where one is unavoidable, at a language or ABI boundary or a handle's reserved null slot, there's exactly one per type, named, checked through the type's own predicate (`_NONE` plus `_is_valid`), never colliding with a legal value. Enum `_COUNT` bounds an array, it isn't a value anything may hold.
  - Never overload one return channel with both a value and an error.
- Handles over pointers for anything in a table. Options structs and designated initializers over long positional parameter lists.
- C: tunables are `#define`s so a consumer can override them from the command line.
- The API file is the manual. Every public header opens with a block: what the module is for, a flat overview of every function in it, a copy-pasteable example of the common path, and the reasoning including what was tried and why it lost. Non-obvious functions get their own example.
- Docs live as close to what they describe as the language allows: file block above the module, doc comment above the declaration, why-comment above the line. A fact in a separate document rots; one above the code gets edited by whoever changes it.
- REST is uniform and generated from one place: a router module per resource exporting its path constant and router, merged at the root; typed request and response structs beside the handler; DTOs as the only thing crossing the wire, with total conversions to and from the domain model; every handler documenting auth, permissions and every status code including the error ones; cross-cutting concerns as layers and preconditions as extractors, so a handler taking a `User` can't run unauthenticated; checked-in `.http` files per resource.

## Memory

Manual memory management. Always know what a subsystem allocates, from where, and for how long. A GC is not a memory strategy; where the language forces one, still own the lifetime.

- Prefer the stack: fixed-size buffers and scoped values first. Bound every stack allocation sized from data and assert the bound as load-bearing. An unbounded `alloca` is a stack clash, not a crash.
- Allocate at startup, then stop. Arenas and pools sized once from the real distribution, steady state allocating nothing. Out of memory becomes a startup failure instead of a 3am one.
- Arenas are the default allocator. Bump-allocate, free the whole region at once, let lifetime be a scope: a startup arena read-only after init, a per-frame temp arena reset every frame, a per-job scratch arena taken from a pool reserved at startup and reset when the job ends.
- An arena isn't thread safe on purpose; a lock would be most of a bump allocator's cost. One arena per thread. Only the process-wide registry and callsite tables are shared, and those are atomic.
- Reuse instead of reallocating: pools and free lists for churning fixed-size objects, capacity reserved once, buffers cleared instead of freed, zero allocation in hot loops.
- Every allocator is introspectable: live stats per arena (used, capacity, peak, regions), per-callsite attribution, a registry walking every live arena, a debug callback logging every alloc, reset and destroy.
- Ownership is explicit in the API: who allocates, who frees, which arena, how long it lives. No hidden allocation; a call that allocates says so, and a caller that can't afford it gets a variant taking an arena or a buffer.

## Robustness & Security

After startup, no operating error may take the program down: not malformed input, not a full table, not a failed allocation, not a hostile peer. Broken invariants are the opposite case and crash on purpose, see Tiger Style.

- Check every fallible return at the call site and either handle it there or propagate it with context; never drop it. On failure unwind partial state, despawn what was spawned, free what was allocated, and return something the caller can act on.
- Every input boundary is untrusted: files, network, IPC, plugins, CLI arguments, env, clipboard, savegames.
- Parse into new types, don't validate. A validator returns a bool and leaves you holding the same unchecked value, so the check gets repeated everywhere and eventually isn't. A parser returns a type that can only exist if the input was good.
  - Parse once, at the boundary. Everything downstream takes the parsed type and nothing re-validates, because nothing can be handed the unparsed form.
  - Every constrained value gets its own type: `Email`, `UserId`, `NonEmpty<T>`, `Utf8Path`, `Sanitized<Html>`, `Meters`. Newtypes with a private field and a fallible constructor (aliri_braid in Rust, an opaque handle plus `_from_str` in C). A `String` that is sometimes an email is not a type.
  - `parse` returns the type or an error saying which rule failed and where. Never a partially valid value, never a silent repair. Same going out: render from the typed value, so escaping happens in one place.
- No unchecked arithmetic, index or cast. Nothing unbounded that remote input can drive.
- Rust: operating errors never panic in library code (no `unwrap`/`expect` on fallible input, `forbid(clippy::unwrap_used)`). Invariant asserts are the intended panic path, and `panic = "abort"` makes them crash-only.
- Probe the environment at startup, in one place, never mid-operation. Every external binary, shared library, plugin, service and file the program needs, with versions checked.
  - Mandatory missing: stop before any work starts and say what's missing, what it's for, and the command that installs it. Never a half-run that fails three steps in.
  - Optional missing: run with that feature off, log it once, tell the user what's degraded and how to enable it. An optional dependency that can take the program down isn't optional.
  - Recover where recovery is honest: a bundled or vendored copy, a slower pure-code path, a different backend. Fall back silently to something worse only when the difference doesn't matter.
  - Never trust `PATH` or a bare name. Resolve the binary, check it's executable, check the version, pass the resolved path onward. A binary that appears mid-run is a supply chain problem.
- Penetration testing is part of QA. Threat-model the boundaries and attack them: authn/authz bypass, injection, deserialization, path traversal, SSRF, resource exhaustion, TOCTOU, integer overflow, use-after-free. Findings become tests.
- Sanitizers are part of the `debug` and `test` builds: address, leak, thread, undefined, unsigned-integer-overflow. Suppressions checked in, each entry justified.
- Least privilege by default. No ambient credentials, secrets from the environment only, dependencies license- and source-allowlisted, artifacts signed.

## Testing

Strong methods over weak ones, in descending value:

1. Deterministic simulation over the real system. Everything non-deterministic sits behind an interface the simulator controls, one seed drives the run, time is simulated rather than waited on, and faults are injected on purpose: disk corruption, torn writes, partitions, delays, reordering, dropped and duplicated messages, restarts at arbitrary points. The assertions are the oracle, so a failing seed is a complete replayable bug report. Run it continuously with random seeds and keep every seed that ever failed.
   - Fault and hardware injection is part of the simulator, not a mode bolted on later. Every boundary the simulator owns is allowed to lie:
     - Network: drop, duplicate, delay, reorder and resend packets, mutate them (flipped bits, truncation, garbage bytes), reset connections mid-message, partition nodes and heal the partition.
     - Dependencies: the database, cache or queue disappears for a window and comes back. Slow answers, timeouts, a pool handing out dead connections, a reply for a request that was already retried.
     - Storage: torn and misdirected writes, bit rot on read, an `fsync` that reports success and lost the data, a full disk.
     - Hardware and process: crash and restart at any point, clock jumps and skew, allocation failure, a thread starved for seconds.
   - The seed picks which faults fire and when, so a failing schedule replays exactly. Fault probabilities are tunables; a run where none of them fire proves nothing.
   - Under fault the contract is the oracle: every operating error is handled, no invariant breaks, no acknowledged write is lost, and the system converges once the fault clears. Assert liveness too, not only safety.
2. Formal verification and refinement types (kani, flux) for invariants that must hold for all inputs.
3. Fuzzing (afl) on every parser and boundary, corpus committed, every crash kept as a regression case. A standing job, not an exercise.
4. Property tests (proptest): state the law, not the example.
5. Table-driven cases (rstest) for known edge cases.
6. Unit tests last, for what nothing above reaches.

The tools named are Rust's; other languages use their equivalent (C: CBMC, AFL++ or libFuzzer; Python: hypothesis; TypeScript: fast-check).

- Determinism wherever a bug must be reproducible: never an unseeded RNG; derive all randomness from the run seed or hash a counter.
- Benchmark what matters and keep the benchmarks in the repo; a performance claim without one is a guess. Benchmarks answer whether this version is faster than that one, profiling answers where the time goes, and neither answers the other's question.
- Benchmarks build optimized and without sanitizers; a sanitized build measures the sanitizer. Throughput comparisons report the best of many runs rather than the mean, since slow samples are contamination; latency reports the tail. Print the spread so a wide one is visible.
- Coverage is instrumented, reported by its own command, over the library only.

## Observability & Introspection

Two questions must be answerable for every subsystem at any moment: how long does it take, and how much memory does it use. If either needs a guess, the instrumentation is missing. It goes in before it's needed, not after a problem appears.

- Logging: levels `TRACE` to `PANIC`, a bounded set of pluggable sinks, fixed-size buffers, no allocation on the log path. Structured json in services, human output in terminals.
- One crash funnel. Assertion, panic, an error that propagated to the top unhandled, and hardware fault all end at a single raise point where observers register, which is what makes crash reports, opt-in telemetry and a crash overlay possible instead of three half-implementations. Observers can't cancel a crash; only the test harness may.
- Reflection: one generated runtime type description drives everything generic over a struct it wasn't written for: property panels, scene and save files, undo snapshots, debug dumps, serialization. The alternative is per-field code in each, which is what rots.
  - Generated from source annotations (`@reflect`, `@tag`, `@skip`), never a separate schema. Tables are `const` data: image size, zero startup work, no registration.
  - Emit source text (`offsetof(T, f)`, `sizeof(F)`) and let the compiler compute layout. A generator that computes offsets is reimplementing an ABI.
  - State the limits in the header, untagged unions unreadable, bitfields undescribed, instead of failing quietly.
- Tracing: nested timed spans per subsystem and per request or frame, trace id carried across every boundary. A slow frame must be explainable from its own trace without reproducing it.
- Scoped profiling: `perf_time_this_scope` / `perf_time_this_function`, compiled into dev builds and out of release builds of desktop and game binaries (services keep tracing and a sampling profiler on in prod), plus a `run profile` mode that records and a command that reads it back.
- Debug overlay: frame time, worst case in the window, cost breakdown. Opt-in, free when off, showing the number worth optimizing against rather than the flattering one.
- Services get prometheus metrics, tracing middleware, log aggregation and continuous profiling, wired at startup on fixed paths, blocked from public access by the proxy.
- Build metadata (commit, build time, mode, flags) compiled in, queryable at runtime, printed in the crash report.

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
- In-code documentation is not a comment and runs as long as it needs: API docs (doc comments `///`, `/** */`, docstrings, the file/module header block described under API Design) the note on a workaround for a dependency bug, the derivation of a named constant, and a rejected alternative that still constrains the code (in the module header block). It documents the contract or the constraint, not the debugging history.
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

## Tooling & Reproducibility

- One entry point per repo: a `justfile`, a `Makefile`, or a custom CLI. Run it bare and it lists everything it can do. Subcommands nested verb then noun, unlike identifiers: `run debug`, `run test`, `run bench`, `build release-linux`, `check --strict`.
- Every command and flag carries its description in the same table that parses it, so help, usage and completions are generated from the definition and can't drift.
- The same commands run locally and in CI. Bad input prints the error and the usage and exits non-zero, never a panic and a stack trace.
- Modes are first-class and symmetric: `debug` (sanitized, hot reload, slow), `dev` (optimized, hot reload, no sanitizers), `release`, plus `test`, `bench`, `coverage`, `profile`. For services: `dev`, `prod`, `test`, `bench`.
- devenv for reproducible environments, `devenv.lock` committed. One `devenv shell` gives the exact toolchain, LSPs, formatters, linters and services. No "install these twelve packages first".
- Simple installs: one command from a fresh clone, one self-contained artifact for users. A static binary or a single container, no runtime to install, no system-wide state, and uninstall is deleting it.
- All dependencies pinned exactly (`=1.0.102`, submodule SHAs, pinned toolchain, digest-pinned images and CI actions), lockfiles committed. No floating versions anywhere. Published libraries are the exception: they declare compatible ranges and pin through the committed lockfile.
- Vendored third-party code lives in `vendor/`, is built by the same entry point, and is never edited in place.
- Optional heavy dependencies are optional features behind a build option, off by default, with the cost in a table: what it links, what it needs installed, what it adds to the binary.

## Infrastructure

Every choice here is judged by how expensive it is to leave.

- Everything must be able to run locally: the full stack, from database to queue to the app itself, comes up on a laptop with one command and no network dependency on a hosted service.
- Open formats and protocols only, for storage, config, wire and export: sqlite, postgres, plain text, json, toml, csv, parquet, HTTP, S3-compatible object storage, OpenTelemetry, prometheus. Nothing that needs a specific vendor's client to read.
- The user's data is theirs: everything the program stores exports whole, in a documented format, by one command, and imports back.
- Rented VPS or dedicated boxes over hyperscaler managed services. A hyperscaler is a fine place to rent a machine and a bad place to buy an ecosystem: once the queue, the auth, the functions and the database are theirs, the price is whatever they say and leaving is a rewrite.
- Prefer software that runs anywhere, so the same stack comes up on a laptop or any VPS: postgres over a managed proprietary database, redis or postgres over a hosted queue, minio over one vendor's bucket semantics, a plain container over a proprietary runtime.
- Docker for packaging. If orchestration is needed, docker swarm: same compose file, a day to learn. Kubernetes needs a reason large enough to justify a permanent operator's worth of complexity, and "we might scale" is not it.
- Infrastructure as code, committed, portable enough that the provider is a variable rather than an assumption. The same definitions bring up dev, test and prod.
- Self-host what's reasonable: metrics, logs, traces, dashboards, object storage, CI runners where it pays.
- A service dependency is a dependency like any other: pinned, wrapped behind your own interface, replaceable without touching the program.

## Git

Before an MVP exists, git is a backup tool and nothing else. Commit whatever, whenever, broken, with whatever message. None of the rules below apply yet, except the attribution rule, which always applies; forcing the rest costs real work to buy nothing. A repo with a tag, CI or other contributors is past its MVP; when unsure, ask. They switch on at the MVP, all at once, and embarrassing scratch history gets squashed into one commit. A repo running `l-spec-driven-development` follows its branch, PR and trace rules from its first spec, MVP or not; this exemption covers only repos not using it.

- One project, one repo, everything versioned with the code it describes: services, client, infrastructure, deployment, CI workflows, docs, tooling, benchmarks, fuzz corpora, issue and PR templates, and the planning itself (`TODO.md`, `todo.org`, ADRs). Nothing that describes the project lives in a wiki, or in a tracker outside the forge that hosts the code.
  - Proximity is the rule: one commit changes the code, its test, its docs and its deployment together. A change that can't be one commit means two things that should have been one file apart.
  - No splitting a project across repos, no submodule maze; submodules are for vendored third-party code only.
- Rebase, never merge commits. Linear history, `pull --rebase`, rebase onto the base before landing. Bisect has to work.
- The trunk is `master`. Branching scales with the project:
  - Small or solo: trunk based. Commit straight to `master`, keep it green, keep changes small. CI runs on every push, not only on PRs, since that's where the code lands.
  - Stable or multiple people: short-lived feature branches off `master`, one PR each, rebased and deleted after landing.
  - With production: `prod`, `dev` as the trunk in place of `master`, and feature branches off `dev`. Features land on `dev`, `dev` promotes to `prod`, and a hotfix branches off `prod` and lands on both.
- Project management is a todo list or a kanban board, nothing else: a `TODO.md` in the repo while solo, a three or four column board once there are issues and people. No sprints, story points, estimates, burndown, standup ritual, or tool that needs its own maintenance.
  - Columns are states the work is actually in. An issue moves because the work moved, never as a reporting exercise.
  - An issue says what the problem is and how you know it's done. That's the whole format.
  - Kept in the repo or the same forge as the code and PRs, never a separate product.
- Past solo trunk work, every PR has an issue behind it. The issue states the problem and the acceptance criteria before the work starts, PRs and commits reference it (`Refs: #12`), and work with no issue behind it doesn't land. The issue is closed once the change is verified, never auto-closed by landing.
- No partial commits after the MVP. Every commit compiles, runs and passes the tests on its own. A commit that doesn't build breaks bisect and breaks whoever checks it out.
- One commit per logical change. Split unrelated changes, squash fixups before landing, never leave a "wip" or "fix typo" in history.
- Conventional commits, enforced by hook and CI: `type(scope): summary`, imperative, lowercase, no trailing period. Types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `chore`, `revert`. Scope is the module or service.
  - Breaking changes get a `!` after the type and a `BREAKING CHANGE:` footer saying what breaks and what to do instead.
  - One line by default: the `type(scope): summary` line is the whole commit, plus required trailers: `Refs:` when an issue exists, and `Spec:`/`Refs:` where `l-spec-driven-development` runs. Add a body only when the why is not obvious from the summary (reasoning, rejected alternative, measurement), never a body that just restates the summary. The summary says what changed, never how. Footers reference issues (`Refs: #12`), never a closing keyword.
  - Never mention the tool that wrote the code. No `Co-Authored-By` for an LLM/agent, no "generated with"/"created by" line, no model name, no AI/agent/assistant reference anywhere in message, body or footer. The commit reads as the author's own, whoever or whatever produced the diff. This overrides any harness or tool default that adds attribution, in commits and PR bodies alike.
- Changelog and version are generated from history, never hand-edited. `feat` bumps minor, `fix` and `perf` bump patch, `!` bumps major, and the tag, changelog and release notes come out of one CI run when the change lands on the trunk.

## CI / CD

A check that isn't automated isn't happening.

- Every PR runs and must pass: format, lint and static analysis, type check, full test suite, doc build, dependency audit, license and source allowlist, secret scan, and a release build for every claimed target and OS.
- Security checks are PR checks, not a quarterly event: CVE audit, SAST, image scan, and the pentest suite against an ephemeral instance brought up by the same compose or devenv definition used locally.
- Fuzzing runs on a schedule, seeded from the committed corpus. Anything it finds is filed and added as a regression case.
- Benchmarks run on a fixed runner and are tracked over time. A significant regression fails or flags the PR.
- CI invokes the repo's own entry point (`just check`, `./build check --strict`), never a script that exists only in the workflow file. Anything CI does, a developer runs identically.
- Pre-commit hooks cover the fast half, format, lint, typos, secret scan, so the runner is only waiting on the slow half.
- Optimize the loop like any other workflow: cancel superseded runs on the same ref, cache the toolchain, dependency builds and devenv closure, split fast checks from slow so failure lands in under a minute, fan the matrix out in parallel, gate expensive jobs on path filters. Slow CI gets worked around, and a worked-around check is off.
- Green means land. No manually ignored failures, no "flaky, rerun it" as policy; a flaky test is a bug with priority.
- CD builds from a tagged commit only, reproducibly, signs the artifact, attaches the generated changelog and build metadata, publishes. Deploys are automated and roll back on a failed health check.
- Repo hygiene is part of it: issue and PR templates, synced labels, CODEOWNERS, all committed.

## Documentation

- README is minimal: what it is, how to clone, how to bootstrap, how to run.
- Real documentation lives in the code, as described in API Design. Nothing that belongs above a declaration goes into a separate file.
- Every project has a generated API reference: doxygen for C, rustdoc for Rust, typedoc for TypeScript, pdoc for Python. Config committed, built from the same entry point, run in CI so a broken link or missing doc comment fails the build like a lint. Warnings on, undocumented public items reported, doc examples compiled and run as tests where the language supports it. The output is a build artifact, not a commit.
- Everything else is generated from source too: OpenAPI schema and browsable UI from handler annotations and DTO types, served by the app itself; client types generated from the server types; CLI help and completions from the command table. If a document can go stale against the code, it should have been generated from it.
- Where the repo has a spec corpus (`specs/`, see `l-spec-driven-development`), the code implements it and the two never drift: a change to code a spec covers updates that spec in the same commit, however small the change.
- Record decisions with their alternatives: what was tried, what broke, why the current shape won. A rejected approach documented is a bug not reintroduced.

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

## LaTeX and Math

How I write LaTeX and mathematics. Conventions taken from my thesis.

Project layout:

- `main.tex` is a thin composition root: `\documentclass`, `\usepackage[<feature flags>]{header}`, metadata, then one `\section{...}` plus `\input{src/NN_name.tex}` per section. No content lives in it.
- Content lives in gap-numbered source files, `src/00_introduction.tex`, `src/10_tc.tex`, `src/20_...`, leaving room to insert between.
- All preamble lives in a local package `header.sty` loaded with `\usepackage{header}`, never inline in `main.tex`.
- Build with latexmk and the project `.latexmkrc`: precompiled preamble, synctex always on, ids stamped when the `ids` flag is set. It reads the header options from `main.tex`, so it is copied as is and never edited per project.
- `amsart`, `11pt`, `a4paper`. `geometry` for margins, `babel` matching the document language. Bibliography in `references.bib`, `\bibliographystyle{alpha}`, entries grouped under banner comments.
- The abstract states the main theorem and result up front, then says what the article introduces and builds on.

Preamble and macros:

- Organize `header.sty` with banner comments: `OPTIONS`, `PACKAGES`, `OPTIONAL PACKAGES`, `AUTOMATIC LABELS`, `CONFIGURATION`, `THEOREMS`, `HOMEWORK AND EXAMS`, `COMMANDS`, sub-grouped (util, essential math).
- Heavy packages and advanced features are opt-in package options, all off by default: `\usepackage[diagrams, autolabels]{header}` with `tikz`, `diagrams`, `plots`, `graphics`, `code`, `algorithms`, `asymptote`, `glossaries`, `autolabels`, `ids`. Idle costs nothing.
- Systematic single-letter macro families: `\A` to `\Z` blackboard bold, `\cA` to `\cZ` calligraphic, `\fA` to `\fZ` fraktur. Var shortcuts `\vphi`, `\vep`, `\vth`. Upright constants and differentials `\ce`, `\ci`, `\cd`, `\dx`, `\dt`.
- Plain `( ) [ ] \{ \} | \|` in math auto-size via the header, so no hand-written `\left(`. Macros for the rest: `\Sp`, `\Abs`, `\Norm`, `\Res`.
- Named operators via `\DeclareMathOperator` (`\im`, `\id`, `\rk`, `\tr`), with the starred form where the index goes below (`\colim`); categories as `\mathsf` (`\Set`, `\Top`, `\Mfd`), invariants as their own operator (`\TC`, `\cat`, `\secat`, `\wgt`, `\zcl`). Derivative helpers `\derivative`/`\pderivative` via `\NewDocumentCommand`; never redefine a kernel or amsmath macro (`\dfrac`), and letter macros that shadow text commands (`\S`, `\P`, ...) switch on math mode.
- German documents (babel main language german) get German theorem, cref and task names from the header.

Notation habits:

- `\coloneq` is the definitional-equality symbol, used everywhere a term is defined. Plain `=` is only for equalities.
- Maps use `\colon`, never a bare `:`. Encode structure in the arrow: `\twoheadrightarrow` for surjections, `\hookrightarrow` for injections and sections.
- `\emph` a term on first introduction. `i.\,e.,` with a thin space, and spelled that way.
- `align*` is the default display environment. Use `equation` only when the line needs a number and label. Annotate step equalities with `\overset{!}{=}`, `\overset{\cong}{=}`, `\overset{\text{nat.}}{\implies}`.

Theorems, proofs, references:

- `amsthm`, `\theoremstyle{definition}`. One shared counter off `[section]`: `\newtheorem{theorem}{Theorem}[section]`, every other environment numbered `[theorem]` (`lemma`, `corollary`, `definition`, `example`, `axiom`, `remark`, `conjecture`).
- Definitions and theorems carry a bracketed title: `\begin{definition}[topological complexity]`.
- The `proof` environment is nested inside its statement environment as the last block, not written separately after it.
- Reference with `cleveref` `\cref` throughout (`nameinlink`), never a raw `\ref`. Set `\crefname` for every environment including irregular plurals (`Lemmata`).
- Labels are namespaced by the kind written out, never abbreviated, with a kebab-case descriptive slug: `definition:path-loop-space`, `theorem:cts-motion-planner-exists-iff-contractible`, `lemma:...`, `corollary:...`, `example:...`, `axiom:...`, `remark:...`, `conjecture:...`, `equation:...`, `chapter:...`, `section:...`, `subsection:...`. Diagrams labelled with `\label[diagram]{diagram:...}`.
  - The `autolabels` flag generates exactly these from titles: `\section{Set Theory}` gets `section:set-theory`, `\begin{lemma}[Zorn]` gets `lemma:zorn`. Hand-written labels follow the same scheme.
  - The `ids` flag adds a stable `<kind>:<ID>` per theorem from `[Zorn|B6AFE]`, which survives renaming the title; reference it where the title may change.
- Cite with `\cite{bibkey}`, locators as `\cite[Proposition 2]{bibkey}`. bib keys are short descriptive slugs.
- Commutative diagrams via `tikz-cd` inside the custom centered `\begin{diagram}` environment. Mark pullback and pushout corners with `\ulcorner`/`\lrcorner` (`phantom`, `very near start`), use `bend`/`shift` for parallel and curved arrows.
- Draft markers live as macros, not stray text: `\todo`, `\citationneeded`, `\referenceneeded`, color helpers `\inred` and friends. Remove them before the final build.
