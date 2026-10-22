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
- `configs/secrets/state/`: private app state that is no credential (dalamud, ffxiv, wallpapers, drift reports,
  firefox's noscript list, repositories), plaintext so backups diff and delta; readable locked.
- `configs/secrets/<module>/`: the owner's modules (group `secrets`, plaintext code): `yubikey`, `capgemini`,
  `weblinks`. `dot sync` refuses to commit any new or changed file outside `keys/`, `state/` and the module dirs.
- `configs/base/yubikey/`: what a fresh install reads before the submodule exists: the sealed git-crypt key
  `secrets.key.age`, one `age-<serial>.identity` and `ssh-<serial>` stub per enrolled YubiKey.
- `configs/secrets/yubikey/`: `recipients.txt` (offline recovery key), `RECOVERY.md`, and `u2f_keys`, the FIDO keys it
  maps in `/etc/u2f_mappings` to each login in root's `/var/lib/dotfiles/owners` (the logins installed with an
  `secrets` profile: bootstrap, `adduser-dotfiles --profile`); `base/pam` reads that file. Its `link` merges
  `keys/age.txt` and the enrolled identities into `~/.config/sops/age/keys.txt`.

## Unlock and check

```bash
nu -c 'use scripts/lib/secrets.nu *; if (secret-is-plaintext configs/secrets/keys/pgp_privatekey.asc) { "unlocked" } else { "locked" }'
./scripts/dot.nu secrets unlock       # pulls the submodule, then unlocks; one touch each
./scripts/dot.nu secrets lock         # back to blobs
```

`dot apply` runs `unlock` itself when the profile has `secrets`. Without a YubiKey, an already pulled worktree
unlocks through the PGP key; `unlock --identity <file>` is the recovery path. Unlock needs a person to touch the key:
ask, do not wait in a loop.

Touch steps (`with-touch` in `scripts/lib/yubikey.nu`) run on the terminal with only a 15min stall cap: the pull clones
the whole submodule (~300 MB), so a short per-attempt timeout kills it mid-clone and restarts it forever, each retry
wanting another touch, which looks like "touched, nothing happens". `age-plugin-yubikey` prints no touch prompt; the
key's blink is the only cue. Without `--foreground`, `timeout` puts the child in its own background process group: the
moment ssh reads `/dev/tty` after the touch (seen live on the ISO: the whole git/ssh chain in state `T`, stopped by
SIGTTIN) it freezes invisibly until the cap kills and restarts it. Ctrl+C on the console also misses that group, leaving it
holding the key: an `age -d` tried by hand alongside then hangs without a blink. pcscd on the bare ISO serves root
without polkit (`ykman piv info` works there); installing polkit would only tighten it.

The pull's ssh stub `configs/base/yubikey/ssh-<serial>` is public, so it is committed passphrase-protected (allowed in
`.gitleaks.toml`); `stub-decrypt` asks that passphrase once on the terminal into a 600 temp copy before the touch loop,
and unattended (no tty) skips the pull rather than wait on a prompt. `configs/secrets/keys/yubikey/ssh-<serial>`, the
copy `link` installs as `~/.ssh/id_ed25519_sk`, is unencrypted under git-crypt. Check a stub with
`ssh-keygen -y -P "" -f <600 copy>`: it fails on an encrypted one.

## Use in a module

- `link` verb: read `$env.DOTFILES/configs/secrets/keys/<file>` and guard with `secret-is-plaintext`, skipping with a
  message when locked (see `configs/core/ntfy/mod.nu`).
- `system` verb: never reads `configs/secrets/keys/` (a secrets-group module's own plaintext files ride in the root
  copy like `configs/`). `dot apply` streams the files named in `SYSTEM_SECRETS`
  (`scripts/lib/system.nu`, plus this host's `initramfs-ssh/<hostname>/sshkeydir/.ed25519.sk` and the platform's
  `wireguard`; `system-secrets`) in its archive to `system-apply.nu`, which unpacks them to a tmpfs
  `$DOTFILES_SECRETS` and deletes everything not on that list. Read `$DOTFILES_SECRETS/<path>` (relative to
  `configs/secrets/keys/`, subdirs kept; a locked file is left out).
- State restored from `state/` or `keys/` that a `backup` verb carries back: guard the backup with
  `secret-seed-guard <marker> <witness> <label>`, which fails when live state exists that the repo never seeded (see
  `configs/gaming/dalamud/mod.nu`).

## Add a secret

1. Unlock, then put the file under `configs/secrets/keys/` (subdirs are fine); git-crypt encrypts it on commit.
   Anywhere else in `configs/secrets/` it would be committed in plaintext: `state/` is for what may be.
2. A system module needs it: add its path to `SYSTEM_SECRETS` in `scripts/lib/system.nu`.
3. `dot sync` commits and pushes the submodule, then the main repo. Agents never do.
4. Writing into `configs/secrets/` while locked would stage plaintext into blob paths: a script that writes there first
   checks `secret-is-plaintext` on a witness file (`pgp_privatekey.asc`) and stops when it is locked.
