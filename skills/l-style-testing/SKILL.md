---
name: l-style-testing
description: "Luca's rules for testing and observability: the testing order (deterministic simulation with fault injection, formal verification, fuzzing, property tests, table-driven, unit), benchmarks, plus logging, tracing, profiling, reflection and the crash funnel. Load alongside the l-style core when writing tests, benchmarks, or instrumentation in Luca's name."
---

# l-style: testing and observability

The on-demand part of `l-style` for proving code works and seeing what it
does at runtime. Load the `l-style` core first; the Tiger Style assertions
this order relies on as its oracle live in `l-style-architecture`.

## Testing

Strong methods over weak ones, in descending value:

1. Deterministic simulation over the real system. Everything non-deterministic sits behind an interface the simulator controls, one seed drives the run, time is simulated rather than waited on, and faults are injected on purpose: disk corruption, torn writes, partitions, delays, reordering, dropped and duplicated messages, restarts at arbitrary points. The assertions are the oracle, so a failing seed is a complete replayable bug report. Run it continuously with random seeds and keep every seed that ever failed.
   - Fault and hardware injection is part of the simulator, not a mode bolted on later. Every boundary the simulator owns is allowed to lie:
     - Network: drop, duplicate, delay, reorder and resend packets, mutate them (flipped bits, truncation, garbage bytes), reset connections mid-message, partition nodes and heal the partition.
     - Dependencies: the database, cache or queue disappears for a window and comes back. Slow answers, timeouts, a pool handing out dead connections, a reply for a request that was already retried.
     - Storage: torn and misdirected writes, bit rot on read, an `fsync` that reports success and lost the data, a full disk.
     - Hardware and process: crash and restart at any point, clock jumps and skew, allocation failure, a thread starved for seconds.
   - The seed picks which faults fire and when, so a failing schedule replays exactly. Fault probabilities are tunables; a run where none of them fire proves nothing.
   - Faults are weighted actions in the same table as the normal actions, not a separate injector. The fault then appears in the history, replays from the one seed and is reported by name. A separate injector with its own generator needs two things seeded and stepped in lockstep to reproduce.
   - Under fault the contract is the oracle: every operating error is handled, no invariant breaks, no acknowledged write is lost, and the system converges once the fault clears. Assert liveness too, not only safety.
2. Formal verification and refinement types (kani, flux) for invariants that must hold for all inputs.
3. Fuzzing (afl) on every parser and boundary, corpus committed, every crash kept as a regression case. A standing job, not an exercise.
4. Property tests (proptest): state the law, not the example.
5. Table-driven cases (rstest) for known edge cases.
6. Unit tests last, for what nothing above reaches.

The tools named are Rust's; other languages use their equivalent (C: CBMC, AFL++ or libFuzzer; Python: hypothesis; TypeScript: fast-check).

- Every test runs without a human in the loop. The agent working on a project can run the whole suite itself, end to end included: no sudo, no password, no hardware key, no click. A test that needs root or a person is redesigned to run unprivileged (user namespaces, rootless VMs, fakes at the boundary), or it is not part of the suite. The one owner-only step (unlocking secrets) is faked or skipped in tests, never required.
- A failure explains itself. Comparisons report what each side held, not just that they differ. A failing test or simulation run prints its seed, the build metadata, the last log lines and the trace of its own run, so the first failure is enough to find the cause without a rerun. A test that can only say "false" is half a test.
- Tests are granular: one behaviour per test, named for the requirement it proves (`spec003_r004_...` under a spec), so a failure names what broke before anyone reads the body. One test program per unit under test is the file-level packaging; inside it, each behaviour is its own named case, not one monolithic assert.
- Two assertion kinds, used deliberately. A hard assert is the invariant oracle: a violated one stops the run at once (Tiger Style, `l-style-architecture`). A soft check inside a test records a mismatch, reports both sides, and lets the case run on, so one run surfaces every failed expectation instead of only the first. Expectations in a test are soft checks; invariants anywhere are hard asserts.
- Writing and editing your own tests alongside your code is normal and good (test-driven development is encouraged). The separation rule is narrower and applies only to a graded or multi-agent pipeline where an independent grader or tester persona owns the oracle (`l-spec-driven-development`, the task modes): there the implementer does not see or edit the tests, graders, seeds or fault tables while writing the code. Reward hacking is real and grows with model strength, so given sight of the check a model hardcodes the expected value, weakens an assertion, loosens a seed or shrinks the fault space to turn the bar green. In that pipeline, graders are randomized or property based so they cannot be special cased, and an independent reviewer who never saw the implementation confirms the change touched implementation only, not the assertions, seeds or fault injection.
- A claim in a planning doc or a status line is not evidence. A feature is finished when a real caller in the tree exercises it and that caller runs in CI, and for anything visual when a human has looked at it. Tests green against code nothing calls prove nothing; verify against what runs, not against what a document says ran.
- Trust the gate, not the feeling. A measured check (the test, the benchmark, the profile) decides whether work is done or fast, never an impression: self-assessed speedups are measurably unreliable, with developers reporting faster while running slower.
- Tests run with assertions, logging and tracing on. An instrumented build that never runs in CI is instrumentation nobody reads.
- Determinism by counter hash, not a stateful RNG: every draw is `hash(seed, step index, draw index)`. Adding a draw in one step or subsystem then leaves every other step's and subsystem's draws where they were, and appending at the end is free, so an old failing seed still reproduces; a stateful generator reorders every decision after the new draw and loses yesterday's seed. (Inserting mid-step still shifts that step's later draw indices, so append rather than insert.) Never an unseeded RNG.
- Determinism is scoped to the same machine and build unless cross-machine reproducibility is a stated requirement. Simulation speed (sim steps per wall second) is a CI gate like correctness, because faster means more seeds per run. Parallel code carries a test comparing per-subsystem state hashes with one worker thread and with all. On replay, fault producers run in shadow and their would-be inputs are compared against the logged ones.
- Stress tests, per subsystem and for the whole program, at realistic scale: the load a larger real program of this project's scope genuinely reaches (a few thousand entities, 32 to 64 peers, thousands of connections, millions of rows), each with a stated budget it must stay inside. Never an absurd load or a deliberately pathological pattern that is slow by construction: the point is to find and drive real optimization, not to manufacture a failure.
- Benchmark what matters and keep the benchmarks in the repo; a performance claim without one is a guess. Benchmarks answer whether this version is faster than that one, profiling answers where the time goes, and neither answers the other's question.
- Benchmarks build optimized and without sanitizers; a sanitized build measures the sanitizer. Throughput comparisons report the best of many runs rather than the mean, since slow samples are contamination; latency reports the tail. Print the spread so a wide one is visible.
- Coverage is instrumented, reported by its own command, over the library only.

## Observability & Introspection

Two questions must be answerable for every subsystem at any moment: how long does it take, and how much memory does it use. If either needs a guess, the instrumentation is missing. It goes in before it's needed, not after a problem appears, and ships in the same commit as the code it watches. The aim is as much introspection as the system can carry: when a test reveals a problem, the asserts, logs, traces and counters around it already hold the data that explains it.

- Logging: levels `TRACE` to `PANIC`, a bounded set of pluggable sinks, fixed-size buffers, no allocation on the log path. Structured json in services, human output in terminals.
- One crash funnel. Assertion, panic, an error that propagated to the top unhandled, and hardware fault all end at a single raise point where observers register, which is what makes crash reports, opt-in telemetry and a crash overlay possible instead of three half-implementations. Observers can't cancel a crash; only the test harness may.
- Reflection: one generated runtime type description drives everything generic over a struct it wasn't written for: property panels, scene and save files, undo snapshots, debug dumps, serialization. The alternative is per-field code in each, which is what rots.
  - Generated from source annotations (`@reflect`, `@tag`, `@skip`), never a separate schema. Tables are `const` data: image size, zero startup work, no registration.
  - Emit source text (`offsetof(T, f)`, `sizeof(F)`) and let the compiler compute layout. A generator that computes offsets is reimplementing an ABI.
  - State the limits in the header, untagged unions unreadable, bitfields undescribed, instead of failing quietly.
- Tracing: nested timed spans per subsystem and per request or frame, trace id carried across every boundary. A slow frame must be explainable from its own trace without reproducing it.
- Scoped profiling: every subsystem entry point and every hot path gets a timed scope (`nya_scope("name")` and the function-level form), compiled into dev builds of desktop and game binaries (services keep tracing and a sampling profiler on in prod), plus a `run profile` mode that records and a command that reads it back. The scope names stay compiled into release builds too, since the crash report walks the live scope stack: the timing cost goes, the labels do not.
- Fixed-capacity structures register their fill level, so how close each one is to its bound is visible at runtime, not discovered at the crash.
- Debug overlay: frame time, worst case in the window, cost breakdown. Opt-in, free when off, showing the number worth optimizing against rather than the flattering one.
- Services get prometheus metrics, tracing middleware, log aggregation and continuous profiling, wired at startup on fixed paths, blocked from public access by the proxy.
- Build metadata (commit, build time, mode, flags) compiled in, queryable at runtime, printed in the crash report.
