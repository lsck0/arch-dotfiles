# borg

`borg-backup.timer` backs `$HOME` up daily into `~/.local/share/borg-repo/<host>-<created>/`, a repokey-blake2 repo
inside the syncthing folder `borg-<host>` (configs/core/syncthing). Syncthing sends it to the NAS, which keeps it
in its own backups, so the NAS and everything behind it only see ciphertext. The run pauses that folder while
borg writes, so a half-written transaction never syncs, and unpausing rescans it.

Before `create` it runs `scripts/lib/backup-*.sh`, so the app state the checkout keeps (secrets, plasma) is fresh
in the archive; `sync.sh` commits it. Weekly it runs `borg check --repository-only`, monthly it restores
`~/.local/state/borg/canary` from the newest archive and compares it.

A run fails, and failure-notify says so, when the passphrase is missing or secrets are locked. On battery or a
metered link it skips quietly until the last good run (`~/.local/state/borg/last-success`) is three days old.

Each init names its repo by its creation time: a reinstalled host starts a new repo next to the one the NAS still
holds instead of syncing a fresh repo over the old one's files.

## Setup, once per user

```bash
head -c 32 /dev/urandom | base64 > secrets/borg-passphrase   # then ./sync.sh
```

The first run exports the repo key (still encrypted by the passphrase) to `secrets/borg-key-<repo>`. Keep a paper
copy as well, beside the age key:

```bash
borg key export --paper ~/.local/share/borg-repo/<repo>
```

## Restore

```bash
export BORG_REPO=~/.local/share/borg-repo/<repo> BORG_PASSCOMMAND="cat $HOME/projects/arch-dotfiles/secrets/borg-passphrase"
borg list
borg extract --list ::<archive> home/<user>/path/to/restore   # into the current directory
```

Lost the machine: copy the folder back from the NAS (or point `BORG_REPO` at the NAS copy, read only); a damaged
repo `config` takes the key with it, restore it with `borg key import <repo> secrets/borg-key-<repo>`.
