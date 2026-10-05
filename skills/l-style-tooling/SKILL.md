---
name: l-style-tooling
description: "Luca's rules for project machinery: one entry point and symmetric modes, reproducible devenv environments, pinned dependencies, infrastructure (open formats, self-hosting, Docker), the git workflow and conventional commit format, CI/CD, and generated documentation. Load alongside the l-style core when setting up tooling, infra, git, writing a commit, CI, or docs in Luca's name."
---

# l-style: tooling, infra, git, CI/CD, docs

The on-demand part of `l-style` for project machinery. Load the `l-style`
core first. Load this before writing a commit message (the Git section
holds the conventional-commit rules).

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
- Real documentation lives in the code, as described in `l-style-architecture` (API Design). Nothing that belongs above a declaration goes into a separate file.
- Every project has a generated API reference: doxygen for C, rustdoc for Rust, typedoc for TypeScript, pdoc for Python. Config committed, built from the same entry point, run in CI so a broken link or missing doc comment fails the build like a lint. Warnings on, undocumented public items reported, doc examples compiled and run as tests where the language supports it. The output is a build artifact, not a commit.
- Everything else is generated from source too: OpenAPI schema and browsable UI from handler annotations and DTO types, served by the app itself; client types generated from the server types; CLI help and completions from the command table. If a document can go stale against the code, it should have been generated from it.
- Where the repo has a spec corpus (`specs/`, see `l-spec-driven-development`), the code implements it and the two never drift: a change to code a spec covers updates that spec in the same commit, however small the change.
- Record decisions with their alternatives: what was tried, what broke, why the current shape won. A rejected approach documented is a bug not reintroduced.
