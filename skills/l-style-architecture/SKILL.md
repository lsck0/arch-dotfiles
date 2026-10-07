---
name: l-style-architecture
description: "Luca's rules for designing and writing non-trivial code: data oriented procedural programming, Tiger Style assertions, architecture and data flow, API and header design, manual memory management, robustness and security. Load alongside the l-style core when designing or writing a module, an API, a data structure, or any non-trivial code in Luca's name."
---

# l-style: architecture

The on-demand part of `l-style` for designing and writing code. Load the
`l-style` core first (philosophy, naming, code style); this adds how the
code is shaped. The units rule, verb vocabulary and naming shape referenced
below live in the core's Naming section.

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
- Tolerate duplication until the shape is clear. Extract on the third or fourth occurrence, not the second.
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

- Parameters are specific enough to be unambiguous: parsed types not raw ones, a handle not an index, a unit-carrying quantity not a bare `f32` (see the units rule in the l-style core, Naming), an options struct past three parameters or whenever two share a type.
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

- Encode the rules in the types: distinct handles instead of raw integers, newtypes instead of bare strings, enums instead of magic values, units per the units rule in the core Naming section, an options struct so two same-typed arguments can't swap. A parameter list of four `int`s is a bug waiting to be reported as a mystery.
- Illegal states unrepresentable rather than validated. Take parsed types as parameters, never the raw form the caller happens to have.
- Assert the contract at the entry point. Out-of-order calls, use before `init`, use after `destroy`, `end` without `begin`, illegal reentrancy, are detected rather than left undefined.
- Handles carry a generation counter, so a stale one is rejected instead of addressing whatever now occupies the slot.
- Return values that matter are marked, so ignoring one is a warning. Bounds are enforced by the API, not by convention.
- Thread-safety, allocation and lifetime rules stated explicitly and asserted where cheap. Silence makes people guess.

### Naming at the API boundary

The core's Naming section holds the full rule (subject-first shape, verb vocabulary, units, inverse pairs). At the API boundary it also means:

- Inverse verbs ship together, same header, adjacent, same visibility. Teardown accepts every value setup can return.
- Conversions at a boundary are named `<type>_from_<source>` / `<type>_to_<target>`; between two internal types they are a smell.

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
