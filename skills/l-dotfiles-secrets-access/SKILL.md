---
name: l-dotfiles-secrets-access
description: Where secrets live (the git-crypt configs/secrets/ submodule), unlocking with the YubiKey, how modules read them in the user and system layer, and adding one. Load before touching anything under configs/secrets/ or a module that needs a credential.
---

# secrets-access

Never print, copy out or commit a secret's value. Locations only.

## Where

- `configs/secrets/`: private submodule `github.com/lsck0/secrets`. Owner-only: needs the `secrets` profile capability.
- `configs/secrets/keys/`: every secret, the only git-crypt path (`configs/secrets/.gitattributes`). Locked, each
  file starts with `\0GITCRYPT`.
- `configs/secrets/<module>/`: the owner's modules (group `secrets`, plaintext code), e.g. `capgemini`, `weblinks`.
  `dot sync` refuses a new file outside `keys/` that is in no module dir, since it would be committed unencrypted.
- `configs/base/yubikey/`: what a fresh install reads before the submodule exists: the sealed git-crypt key
  `secrets.key.age`, one `age-<serial>.identity` and `ssh-<serial>` stub per enrolled YubiKey.
- `configs/secrets/yubikey/`: `recipients.txt` (offline recovery key), `RECOVERY.md`, and `u2f_keys`, the FIDO keys it
  maps in `/etc/u2f_mappings` to each login in root's `/var/lib/dotfiles/owners` (the logins installed with an
  `identity` profile: bootstrap, `adduser-dotfiles --profile`, `migrations/0003-u2f-owners.nu`); `base/pam` reads that
  file.

## Unlock and check

```bash
nu -c 'use scripts/lib/secrets.nu *; if (secret-is-plaintext configs/secrets/keys/pgp_privatekey.asc) { "unlocked" } else { "locked" }'
./scripts/dot.nu secrets unlock       # pulls the submodule, then unlocks; one touch each
./scripts/dot.nu secrets lock         # back to blobs
```

`dot apply` runs `unlock` itself when the profile has `secrets`. Without a YubiKey, an already pulled worktree
unlocks through the PGP key; `unlock --identity <file>` is the recovery path. Unlock needs a person to touch the key:
ask, do not wait in a loop.

## Use in a module

- `link` verb: read `$env.DOTFILES/configs/secrets/keys/<file>` and guard with `secret-is-plaintext`, skipping with a
  message when locked (see `configs/core/ntfy/mod.nu`).
- `system` verb: never reads `configs/secrets/keys/` (a secrets-group module's own plaintext files ride in the root
  copy like `configs/`). `dot apply` streams the files named in `SYSTEM_SECRETS`
  (`scripts/lib/system.nu`, plus this host's `initramfs-ssh/<hostname>/sshkeydir/.ed25519.sk` and the platform's
  `wireguard`; `system-secrets`) in its archive to `system-apply.nu`, which unpacks them to a tmpfs
  `$DOTFILES_SECRETS` and deletes everything not on that list. Read `$DOTFILES_SECRETS/<file>` (flat: the archive
  packs from `configs/secrets/keys/`).

## Add a secret

1. Unlock, then put the file under `configs/secrets/keys/` (subdirs are fine); git-crypt encrypts it on commit.
   Anywhere else in `configs/secrets/` it would be committed in plaintext.
2. A system module needs it: add its path to `SYSTEM_SECRETS` in `scripts/lib/system.nu`.
3. `dot sync` commits and pushes the submodule, then the main repo. Agents never do.
4. Writing into `configs/secrets/` while locked would stage plaintext into blob paths: a script that writes there first
   checks `secret-is-plaintext` on a witness file (`pgp_privatekey.asc`) and stops when it is locked.
