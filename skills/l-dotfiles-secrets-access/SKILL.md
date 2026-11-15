---
name: l-dotfiles-secrets-access
description: Where secrets live (the git-crypt configs/secrets/ submodule), unlocking with the YubiKey, how modules read them in the user and system layer, and adding one. Load before touching anything under configs/secrets/ or a module that needs a credential.
---

# secrets-access

Never print, copy out or commit a secret's value. Locations only.

## Personal rollout needs the profile AND the YubiKey, both at once

Anyone can install the dotfiles, so the owner's personal configuration rolls out only when both hold: the `secrets`
profile is selected and the owner's YubiKey has unlocked `keys/`. Naming the profile alone leaves a generic, fully
capable desktop.

- A module that rolls out personal config or credentials gates on `owner-unlocked` (both checks,
  `scripts/lib/secrets.nu`), not on `profile-has secrets` alone.
- When it cannot roll out, an owner-only module skips with a one-line log (`bugwarrior`, `projects`); a value gate
  falls back to the generic value (`core/git`'s identity, `core/gnupg`'s default-key).
- One exception: a rollout whose secret use is checked at run time (ssh's `ssh-add.service` and `authorize`,
  protonvpn's `auto-vpn`, failure-notify's `recovery-drill`) gates on `profile-has secrets` alone, so it works after
  an unlock without a re-apply; `configs/base/AGENTS.md` lists them.
- The offline recovery key is for a lost YubiKey, not the normal path.

## Where

- `configs/secrets/`: private submodule `github.com/lsck0/secrets`, only with the `secrets` profile capability.
- `keys/`: every secret, the only git-crypt path. Locked, each file starts with `\0GITCRYPT`.
- `state/`: plaintext app state that is no credential (dalamud, ffxiv, firefox, obs art, plasma's weather place,
  repositories, shimoji, drift); readable locked.
- `configs/secrets/<module>/`: the owner's own modules, plaintext (`yubikey`, `weblinks`, `shell`; `skills` holds
  every agent skill but the public `l-dotfiles*` ones in `skills/`). `dot sync` refuses to commit any new or changed
  file outside `keys/`, `state/` and the module dirs.
- `configs/base/yubikey/`: what a fresh install reads first: sealed git-crypt key `secrets.key.age`, one
  `age-<serial>.identity` and `ssh-<serial>` stub per YubiKey.
- `configs/secrets/yubikey/`: `recipients.txt` (offline recovery key), `RECOVERY.md`, `u2f_keys` (mapped in
  `/etc/u2f_mappings` to each login in `/var/lib/dotfiles/owners`, read by `base/pam`). Its `link` merges
  `keys/age.txt` and the identities into `~/.config/sops/age/keys.txt`.

## Unlock and check

```bash
nu -c 'use scripts/lib/secrets.nu *; secret-is-plaintext configs/secrets/keys/pgp/private.asc'   # true: unlocked
dot secrets unlock       # Luca's: pull the submodule, then unlock; one touch each
dot secrets lock         # Luca's
```

- `dot secrets unlock|lock` are Luca's (YubiKey), never an agent's. With the `secrets` profile `dot apply` and `dot
  sync` unlock by themselves; an apply without a terminal (an agent's) leaves them locked and says so. Without a
  YubiKey a pulled worktree unlocks via the PGP key; `unlock --identity <file>` is the recovery path.
- Unlock needs a person to touch the key: ask, never wait in a loop. `age-plugin-yubikey` prints no prompt; the blink
  is the only cue.
- Touch steps (`with-touch`, `configs/base/yubikey/yubikey.nu`) cap each attempt at 15 min (`TOUCH_ATTEMPT_S`) and
  retry until `TOUCH_WAIT` (30 min): the pull clones ~300 MB, and a shorter attempt cap restarts it forever, each
  retry wanting a new touch.
- `timeout` needs `--foreground`: otherwise ssh reading `/dev/tty` after the touch is stopped by SIGTTIN and hangs
  invisibly. Ctrl+C also misses that group, which keeps holding the key, so a manual `age -d` then hangs without blink.
- pcscd on the bare ISO serves root without polkit.
- The ssh stub `configs/base/yubikey/ssh-<serial>` is committed passphrase-protected (allowed in `.gitleaks.toml`);
  `stub-decrypt` asks once into a 600 temp copy, and without a tty skips the pull. `keys/yubikey/ssh-<serial>`
  (installed as `~/.ssh/id_ed25519_sk`) is unencrypted under git-crypt. Check a stub with
  `ssh-keygen -y -P "" -f <600 copy>` (fails if encrypted).

## Use in a module

- `link`: read `$env.DOTFILES/configs/secrets/keys/<file>`, guard with `secret-is-plaintext`, skip with a message when
  locked (`configs/programming/projects/mod.nu`).
- `system`: never reads `keys/`. `dot apply` streams the files every module names in `meta.secrets` (paths relative to
  `keys/`, `{host}` this machine's hostname; `system-secrets` in `scripts/lib/system.nu`) and the platform's
  `wireguard` to a tmpfs; read one as `system-secret <path relative to keys/>` (a locked file is absent, and the path
  never exists without the secrets).
- State a `backup` verb carries back: guard with `secret-seed-guard <marker> <witness> <label>`
  (`configs/gaming/dalamud/mod.nu`), which fails on live state the repo never seeded.

## Add a secret

1. Luca unlocks; it goes under `configs/secrets/keys/`. Anywhere else in `configs/secrets/` it is committed in
   plaintext.
2. A system module needs it: add its path to that module's `meta.secrets`.
3. `dot sync` commits and pushes (submodule first). Agents never do.
4. Never write into `configs/secrets/` while locked: a script checks `secret-is-plaintext` on `pgp/private.asc`
   first and stops.
