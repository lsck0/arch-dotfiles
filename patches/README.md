# patches

One-shot fixups for state that the modules cannot reach.

Every `system.sh` and `link.sh` reruns on each `config.sh`, so a changed config file reaches every machine on the
next run. What a module cannot do is undo what an *older* config already did: a dropped pacman hook stays in
`/etc/pacman.d/hooks`, a dropped PAM line stays in `/etc/pam.d`, a link it no longer makes stays in `$HOME`. A patch
is the place for those, so converging an existing machine never needs a reinstall.

Two kinds of drift are not patches. A dropped package or unit is removed by the ledger (`scripts/lib/ledger.sh`). A
dangling link into the checkout is pruned by `config.sh`, one into `/home` from `/usr/local/bin` by
`scripts/lib/system-apply.sh`, on every run.

## Two scopes

The file name decides who runs a patch and where its success is recorded:

| name | runs as | when | record |
|---|---|---|---|
| `NN_<slug>.sh` | root, from the root copy `/var/lib/dotfiles/repo` | `system-apply.sh config`, after every `system.sh` | `/var/lib/dotfiles/patches-applied` |
| `NN_<slug>.user.sh` | the user, from `~/projects/arch-dotfiles` | `config.sh`, before every `link.sh` | `${XDG_STATE_HOME:-~/.local/state}/dotfiles/patches-applied` |

A patch is pending until its name is in its record; one that fails stays pending and is retried on the next run.
A fresh machine or user has nothing to undo: `bootstrap.sh` and `adduser-dotfiles` write every patch of the repo
into the new records, so only a patch added *after* a machine or user was set up ever runs there, once.

## Writing one

Name it `NN_<slug>.sh` or `NN_<slug>.user.sh`, with `NN` higher than every existing patch (ordering only). A
system patch is root already, so no `sudo`, and reads no `$HOME`; a user patch never calls `sudo`. Make it
**idempotent** and **safe on a machine that never had the problem**: check before you change, and exit 0 when there
is nothing to do. Exit non-zero to stay pending (for example until a module installed what the patch waits for).

```bash
#!/usr/bin/env bash
# What this undoes, and which change made it necessary.
set -euo pipefail
...
```

`DOTFILES` is the tree the patch runs from (the root copy or the checkout).

## Running

The scope follows who runs it: as root (`sudo`, from the root copy) the machine's patches, as yourself your own.

```bash
scripts/lib/apply-patches.sh                 # pending patches of this scope, in order
scripts/lib/apply-patches.sh --list          # applied / pending per patch
scripts/lib/apply-patches.sh --dry-run       # what would run
scripts/lib/apply-patches.sh --force NN_slug # run one regardless of its record
scripts/lib/apply-patches.sh --mark-applied  # record every patch of this scope as applied, running none
```

Patches are never deleted once pushed: a machine set up before a patch was added still needs it.
