---
name: l-engine
description: "Orientation for nyangine, Luca's C engine and the stack his software is built on (games, desktop apps, server-rendered web, TUI, CLI). A thin pointer: where the authoritative docs live, the dev loop, and the shape of the system. Load before working in nyangine or a project built on it; it defers every exact name to the repo's own generated reference and skills."
---

# l-engine

nyangine (`~/projects/nyangine`) is the C engine that is becoming the one stack for all of Luca's
software: games, desktop applications, server-rendered web, TUI and CLI, composing in one program. It
is data oriented procedural C, built with clang as a unity build, rendered through SDL3's GPU API. This
skill is orientation only. It names where the truth lives and the shape to expect; it does not restate
the API, which would go stale.

Write engine code to the `l-style` core and `l-style-architecture`: load both first. The engine is the
reference implementation of that guide, so the guide explains why the code looks as it does.

## Where the truth lives, in order

- The repo's `AGENTS.md`: the working index, the module table, the layout, the conventions.
- `docs/CHEATSHEET.md`: the generated API reference, the only list of names that cannot be out of date.
  When it and any prose disagree, the header wins. Read it before calling anything; never guess a
  signature from this skill.
- `docs/*.md`: prose per subject. The repo's own `skills/` and its `AGENTS.md` hold the how-to detail
  (`l-auto-memory`); open the one a task needs.
- `TODO.md`: the scope and the ordered plan. Its "Next, in order" list is what to build next, and its
  Findings record the lessons behind past decisions. Read it before choosing what to build.

## The dev loop

- `./build` is a C program that recompiles itself, with nested CLI verbs (`run`, `test`, build modes).
  Run it bare to see what it can do. The same entry point builds, runs, tests and benchmarks.
- A project is a directory with a `project.nya` that names a profile plus the extra components it needs;
  only those compile and link. A game or app is built on the engine this way, not forked from it.
- Hot reload: a generic host loads the app as a shared library through fixed entry functions; state that
  must survive a reload lives in the world, not in globals, and callbacks are looked up by name after a
  reload. The edit-run loop is seconds, by design.

## The shape

Expect these primitives; the cheatsheet has their exact names.

- One system registry wires engine, game and plugin systems in a known order (each declares its `before`
  and `after`, an init and deinit pair, and up to a few per-frame phases). A system declares what it
  needs and provides, so a part with nothing to draw on is refused by name at startup, not mid-run.
- The entity is one fat reflected struct a project extends with its own fields, read and written by
  systems through type and flags. There is no ECS and no per-entity callbacks; that was tried and
  rejected, with the reason recorded.
- Errors are a rich must-use value carrying the chain of calls they passed through, propagated or
  crashed-on explicitly, with results returned through out-parameters zeroed on failure. A boolean is
  only ever a predicate.
- Memory is arenas, not ad hoc allocation; lifetime is a scope. One crash funnel assembles every fault
  into a single report. Profiling is scoped, and the scope names stay in release builds for that report.
- Determinism is built in: every random draw is a hash of seed, step and draw index, and faults are
  weighted entries in the same table, so a failing seed replays exactly.
- Extension is one file following the convention: a system, a plugin, an example. Adding it is the whole
  change; nothing central edits to register it. Scripting today is Lua (signed plugins, a VM with a
  budget each); a flat C ABI that any language binds is the planned general form, per `TODO.md`.

A feature is not finished until a real program calls it (a demo, an example, a test) and that caller
runs; a visible change is not finished until someone has looked at it on screen.
