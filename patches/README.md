# patches

One-shot fixups for state that `config.sh` cannot reach.

`config.sh` relinks every `configs/*/link.sh`, so a changed config file reaches every machine on the next run.
What it cannot do is undo what an *older* config already did to the system: a renamed script leaves a dangling
`/usr/local/bin` entry, a dropped PAM line stays in `/etc/pam.d`, a replaced unit stays enabled. A patch is the
place for those, so converging a second machine never needs a reinstall.

## Writing one

Name it `NN_<slug>.sh`, with `NN` higher than every existing patch. It runs once per machine, in numeric order,
from `config.sh` (and from `apply-patches` by hand). The name is then recorded in
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/patches-applied`.

That record lives outside git, so a fresh install or a wiped state dir replays every patch. Patches are
therefore **idempotent** and **safe on a machine that never had the problem**: check before you change, and
exit 0 when there is nothing to do. A patch that fails stays pending and is retried on the next run.

```bash
#!/usr/bin/env bash
# What this undoes, and which change made it necessary.
set -euo pipefail
...
```

## Running

```bash
apply-patches                                # pending ones, in order
apply-patches --list                         # applied/pending per patch
apply-patches --dry-run                      # what would run
apply-patches --force 00_prune-stale-links   # re-run one
```

Patches are never deleted once pushed: a machine that has been offline for a year still needs the whole chain.
