---
name: l-dotfiles-secrets-access
description: Where secrets live (the git-crypt secrets/ submodule), unlocking with the YubiKey, how modules read them in the user and system layer, and adding one. Load before touching anything under secrets/ or a module that needs a credential.
---

# secrets-access

Never print, copy out or commit a secret's value. Locations only.

## Where

- `secrets/`: submodule `github.com/lsck0/secrets`, every file git-crypt encrypted. Locked, each file starts with
  `\0GITCRYPT`. Owner-only: needs the `secrets` profile capability.
- `configs/base/yubikey/`: the sealed git-crypt key `secrets.key.age`, one `age-<serial>.identity` and
  `ssh-<serial>` stub per enrolled YubiKey, `recipients.txt` (offline recovery key), `RECOVERY.md`.

## Unlock and check

```bash
nu -c 'use scripts/lib/secrets.nu *; if (secret-is-plaintext secrets/pgp_privatekey.asc) { "unlocked" } else { "locked" }'
./scripts/dot.nu secrets unlock       # pulls the submodule, then unlocks; one touch each
./scripts/dot.nu secrets lock         # back to blobs
```

`dot apply` runs `unlock` itself when the profile has `secrets`. Without a YubiKey, an already pulled worktree
unlocks through the PGP key; `unlock --identity <file>` is the recovery path. Unlock needs a person to touch the key:
ask, do not wait in a loop.

## Use in a module

- `link` verb: read `$env.DOTFILES/secrets/<file>` and guard with `secret-is-plaintext`, skipping with a message when locked (see `configs/core/ntfy/mod.nu`).
- `system` verb: never reads `secrets/`. `dot apply` streams the files named in `SYSTEM_SECRETS`
  (`scripts/lib/system.nu`, plus the platform's `wireguard`) in its archive to `system-apply.nu`, which unpacks them to a
  tmpfs `$DOTFILES_SECRETS` and deletes everything not on that list. Read `$DOTFILES_SECRETS/<file>`.

## Add a secret

1. Unlock, then put the file under `secrets/` (subdirs are fine); git-crypt encrypts it on commit.
2. A system module needs it: add its path to `SYSTEM_SECRETS` in `scripts/lib/system.nu`.
3. `dot sync` commits and pushes the submodule, then the main repo. Agents never do.
4. Writing into `secrets/` while locked would stage plaintext into blob paths; `secret_require_unlocked` guards
   scripts that write there.
