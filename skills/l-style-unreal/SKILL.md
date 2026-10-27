---
name: l-style-unreal
description: "Luca's conventions for building a component inside a large third-party engine like Unreal: C++ over Blueprint, an own subsystem table, determinism, and build/test policy. Load alongside the l-style core and l-style-architecture when doing that work."
---

# l-style: unreal

This governs a component I own inside someone else's engine: the engine is a given, the
component is mine and holds to the full standard. The engine's own conventions win only at
the thin glue boundary; everything behind the glue is l-style. Load the `l-style` core and
`l-style-architecture` first; this adds what the engine forces and what I refuse to let it force.

## Logic and the glue boundary

- All simulation and logic is C++. The engine's scripting, visual scripting and animation
  graphs are content-side views of plain-data state, authored by content people, never a
  home for runtime logic. No logic in a visual-script graph or an actor tick.
- Two layers, written down once. A thin glue layer in the engine's own idiom (its type
  prefixes, its reflection macros, its override hooks, its delegates) that only translates
  engine calls into plain calls. Everything behind the glue is plain structs and
  `subject_verb_object` free functions in l-style naming with a folder prefix. Name glue
  files by the engine's convention, plain files by the folder-prefix convention.
- Spawned actors are views of plain state: outputs rebuilt from state at any time, owning no
  movement and no wall-time history, never the source of truth. Level content is found through
  an authoring contract (tags, data layers), never by hard-coded actor names, and never feeds
  back into state.

## Reflection and subsystems

- Use the engine's reflection macros only where they pay: state hashing, the serialization
  codec, snapshots, wire views. Never to obtain engine behaviour as a side effect.
- Prefer one own table of subsystem descriptors (name, lifetime hooks `init`/`tick`/`check`/
  `shutdown`, a state view, declared reads, config keys, a benchmark name) wired in one array
  in a single composition root, in init order, over scattering logic across the engine's
  built-in subsystem types. Nothing else registers anything. Reach the engine only through
  its frame and world hooks; editor worlds get a reduced table and a failed bind never exits
  the editor.
- One runtime module with its tests inside it, until a hard reason splits it. Editor-only
  code is gated by the engine's editor flag in the same module.

## Determinism

- Fixed timestep via the engine's fixed-step mode; sim time is computed from the step index,
  never accumulated from frame deltas.
- Wall clocks and the engine's RNG are banned outside an allowlist file that records a reason
  for each entry. Randomness is seeded per-subsystem streams. No unordered containers in
  state. Parallel code carries a test comparing per-subsystem state hashes with one and with
  all worker threads.
- Every change from outside the step is a record in one input log with a per-record checksum,
  appended so a crash leaves a readable prefix. Replay compares per-subsystem state hashes
  step by step and names the diverging subsystem. Determinism is scoped to the same machine
  and build; cross-machine is a separate, stated requirement.

## External data

- Feed external data through adapters onto one internal model. Adapters add no behaviour and
  may not reach into world or entity state. Mirror the internal model from a shared schema
  one to one, and derive kind ids from the schema's field numbers, never hand-pick them.
- Own a strict codec over the reflection walk for anything leaving the process. Reject an
  engine serializer that loses data or ties the format to the engine version. No engine
  network replication: the component is one authoritative process, and every engine listener
  sits behind a bounding proxy, never facing a peer directly.

## Build, test, deploy

- Development builds with the project's own assertion macros, kept in every build. Do not use
  the engine's check/ensure (compiled out in shipping, or continue past a broken invariant).
- Warnings are errors. Reject an engine facility that fights these rules and record why in the
  decision log, then wrap the lower-level primitive instead.
- Editor automation is headless commandlets, not interactive console commands. Any editor MCP
  is enabled per launch, bound to loopback.
- The parsers and codecs that take untrusted input are an engine-free core subset that builds
  without engine headers, so they fuzz outside the engine's build tool. Deploy the exact
  uncooked build CI tested, unless cooking is a stated requirement and then CI cooks too.
