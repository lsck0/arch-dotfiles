---
name: l-dotfiles-secrets-access
description: The git-crypt configs/secrets/ submodule (keys/, state/, owner modules), YubiKey unlock, the owner-unlocked gate, how link and system verbs read a secret, and adding one. Load before touching anything under configs/secrets/ or writing a module that needs a credential or personal config. Homelab sops secrets are l-homelab-secrets.
---

# secrets-access

Never print, copy out or commit a secret's value; name locations only. `dot secrets unlock|lock` are Luca's (YubiKey
touch), never an agent's. Never write into `configs/secrets/` while it is locked.

## Check before touching

```bash
nu -c 'use scripts/lib/secrets.nu *; secret-is-plaintext configs/secrets/keys/pgp/private.asc'   # true: unlocked
```

Locked files start with `\0GITCRYPT`. Locked and you need it: ask Luca to run `dot secrets unlock`, never wait in a
loop. With the `secrets` profile, `dot apply` and `dot sync` unlock by themselves at a terminal; an agent's apply has
none and leaves them locked, saying so.

## Layout

- `configs/secrets/`: private submodule `github.com/lsck0/secrets`, pulled only with the profile's `secrets` capability.
- `keys/`: every secret, the only git-crypt path.
- `state/`: plaintext app state that is no credential; readable locked.
- `configs/secrets/<module>/`: the owner's own modules, plaintext (`skills` holds every agent skill but the public
  `skills/l-dotfiles*`). `dot sync` refuses any new or changed file outside `keys/`, `state/` and the module dirs.
- `configs/base/yubikey/`: what a fresh install reads first: the sealed git-crypt key `secrets.key.age`, one
  `age-<serial>.identity` and passphrase-protected `ssh-<serial>` stub per YubiKey.
- `configs/secrets/yubikey/`: `recipients.txt` (offline recovery key), `RECOVERY.md`, `u2f_keys` (mapped in
  `/etc/u2f_mappings` to each login in `/var/lib/dotfiles/owners`). Its `link` merges `keys/age.txt` and the
  identities into `~/.config/sops/age/keys.txt`.

## Gate personal rollouts

Anyone can install the dotfiles, so personal config rolls out only when the `secrets` profile is selected and the
YubiKey has unlocked `keys/`.

- Gate on `owner-unlocked` (`scripts/lib/secrets.nu`), not `profile-has secrets` alone. When it cannot roll out, an
  owner-only module skips with a one-line log (`bugwarrior`, `projects`); a value gate falls back to the generic value
  (`core/git`'s identity, `core/gnupg`'s default-key).
- Exception: a rollout that checks its secret at run time gates on `profile-has secrets` alone, so it works after an
  unlock without a re-apply; `configs/base/AGENTS.md` lists them.

## Read one in a module

- `link`: read `$env.DOTFILES/configs/secrets/keys/<file>`, guard with `secret-is-plaintext`, skip with a message when
  locked (`configs/programming/projects/mod.nu`).
- `system`: never reads `keys/`. List the paths in `meta.secrets` (relative to `keys/`, `{host}` is this machine's
  hostname); `dot apply` streams them and the platform's `wireguard` to a tmpfs. Read one as `system-secret <path>`; a
  locked file is absent.
- State a `backup` verb carries back: guard with `secret-seed-guard <dir> <witness>`; it fails on live
  state at `<witness>` the repo never seeded (no `<dir>/.from-secrets`, which `secret-seed-mark <dir>` sets).

## Add one

1. Check it is unlocked (above). Put the file under `configs/secrets/keys/`: anywhere else in `configs/secrets/` it is
   committed in plaintext.
2. A system module needs it: add its path to that module's `meta.secrets`.
3. Luca's `dot sync` commits and pushes (submodule first). Agents never do.

## Gotchas

- `age-plugin-yubikey` prints no prompt; the key's blink is the only cue for a touch.
- Touch steps (`with-touch`, `configs/base/yubikey/yubikey.nu`) cap each attempt at 15 min (`TOUCH_ATTEMPT_S`) and
  retry until `TOUCH_WAIT` (30 min): the pull clones about 300 MB, and a shorter cap restarts it forever.
- `timeout` needs `--foreground`: otherwise ssh reading `/dev/tty` after the touch stops on SIGTTIN and hangs
  invisibly. Ctrl+C misses that process group too, which keeps holding the key, so a manual `age -d` then hangs with
  no blink.
- The ssh stub decrypts once into a 600 temp copy (`stub-decrypt`); without a tty the pull is skipped. Check a stub
  with `ssh-keygen -y -P "" -f <600 copy>` (fails while encrypted).
- No YubiKey: a pulled worktree unlocks via the PGP key; `dot secrets unlock --identity <age file>` is the recovery
  path. pcscd on the bare ISO serves root without polkit.
