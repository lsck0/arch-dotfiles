# patches

One-shot fixups for state that `config.sh` cannot reach.

`config.sh` relinks every `configs/*/link.sh`, so a changed config file reaches every machine on the next run.
What it cannot do is undo what an *older* config already did to the system: a dropped pacman hook stays in
`/etc/pacman.d/hooks`, a dropped PAM line stays in `/etc/pam.d`. A patch is the place for those, so converging an
existing machine never needs a reinstall.

Two kinds of drift are not patches. A dropped package or unit is removed by the ledger
(`scripts/lib/ledger.sh`). A dangling link into the checkout is pruned by `config.sh` on every run.

## When a patch runs

`apply-patches` (run by `config.sh`, or by hand) applies a patch only when both hold:

- It is **not already applied** on this machine. Success is recorded in
  `${XDG_STATE_HOME:-~/.local/state}/dotfiles/patches-applied`, so a succeeding patch never runs twice.
- It is **younger than this machine's install**. The first run stamps the install date in
  `${XDG_STATE_HOME:-~/.local/state}/dotfiles/install-date`; a patch whose last commit predates it belongs to an
  earlier machine and never runs here.

So a fresh install replays nothing: every patch already in the repo is older than its install. Only a patch
committed *after* a machine was set up runs there, once, when that machine next pulls. A patch that fails stays
pending and is retried on the next run.

## Writing one

Name it `NN_<slug>.sh`, with `NN` higher than every existing patch (ordering only; age comes from git). Make it
**idempotent** and **safe on a machine that never had the problem**: check before you change, and exit 0 when
there is nothing to do.

```bash
#!/usr/bin/env bash
# What this undoes, and which change made it necessary.
set -euo pipefail
...
```

## Running

```bash
apply-patches                 # pending, younger-than-install patches, in order
apply-patches --list          # applied / pending / preinstall per patch
apply-patches --dry-run       # what would run
apply-patches --force NN_slug # run one regardless of install date or record
```

Patches are never deleted once pushed: a machine set up before a patch was committed still needs it.
