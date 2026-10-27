---
name: l-dotfiles-secrets-access
description: Where secrets live (the git-crypt configs/secrets/ submodule), unlocking with the YubiKey, how modules read them in the user and system layer, and adding one. Load before touching anything under configs/secrets/ or a module that needs a credential.
---

# secrets-access

Never print, copy out or commit a secret's value. Locations only.

## Personal rollout needs the profile AND the YubiKey, both at once

The dotfiles are installable by anyone, so the owner's personal configuration is gated by two independent facts that
must both hold, never one alone: the `secrets` profile is selected, and the owner's YubiKey is present (it is what
decrypts `keys/`). Selecting the owner profile is necessary but not sufficient. Without the key the machine stays a
generic, still fully capable desktop; it never rolls out the owner's personal things just because someone named the
profile. A module that rolls out personal config or credentials gates on `owner-unlocked` (the two checks together, in
`scripts/lib/secrets.nu`), not merely `profile-has secrets`. When it cannot roll out, an owner-only module skips with
a one-line log (as `bugwarrior`, `ntfy`, `projects` do), and a value gate instead defaults the owner value to the
generic one (as `core/git`'s identity and `core/gnupg`'s default-key do); either way a keyless install gets the
generic layer, never the owner's. The offline recovery key is the deliberate exception for a lost YubiKey, not the
normal path.

## Where

- `configs/secrets/`: private submodule `github.com/lsck0/secrets`, only with the `secrets` profile capability.
- `keys/`: every secret, the only git-crypt path. Locked, each file starts with `\0GITCRYPT`.
- `state/`: plaintext app state that is no credential (dalamud, ffxiv, noscript list, repositories); readable locked.
- `configs/secrets/<module>/`: the owner's own modules (`yubikey`, `weblinks`, and the like), plaintext. `dot sync` refuses
  to commit any new or changed file outside `keys/`, `state/` and the module dirs.
- `configs/base/yubikey/`: what a fresh install reads first: sealed git-crypt key `secrets.key.age`, one
  `age-<serial>.identity` and `ssh-<serial>` stub per YubiKey.
- `configs/secrets/yubikey/`: `recipients.txt` (offline recovery key), `RECOVERY.md`, `u2f_keys` (mapped in
  `/etc/u2f_mappings` to each login in `/var/lib/dotfiles/owners`, read by `base/pam`). Its `link` merges
  `keys/age.txt` and the identities into `~/.config/sops/age/keys.txt`.

## Unlock and check

```bash
nu -c 'use scripts/lib/secrets.nu *; if (secret-is-plaintext configs/secrets/keys/pgp_privatekey.asc) { "unlocked" } else { "locked" }'
./scripts/dot.nu secrets unlock       # pull the submodule, then unlock; one touch each
./scripts/dot.nu secrets lock
```

- `dot apply` unlocks itself with the `secrets` profile. Without a YubiKey a pulled worktree unlocks via the PGP key;
  `unlock --identity <file>` is the recovery path.
- Unlock needs a person to touch the key: ask, never wait in a loop. `age-plugin-yubikey` prints no prompt; the blink
  is the only cue.
- Touch steps (`with-touch`, `configs/base/yubikey/yubikey.nu`) have only a 15 min cap: the pull clones ~300 MB, and a
  shorter timeout restarts it forever, each retry wanting a new touch.
- `timeout` needs `--foreground`: otherwise ssh reading `/dev/tty` after the touch is stopped by SIGTTIN and hangs
  invisibly. Ctrl+C also misses that group, which keeps holding the key, so a manual `age -d` then hangs without blink.
- pcscd on the bare ISO serves root without polkit.
- The ssh stub `configs/base/yubikey/ssh-<serial>` is committed passphrase-protected (allowed in `.gitleaks.toml`);
  `stub-decrypt` asks once into a 600 temp copy, and without a tty skips the pull. `keys/yubikey/ssh-<serial>`
  (installed as `~/.ssh/id_ed25519_sk`) is unencrypted under git-crypt. Check a stub with
  `ssh-keygen -y -P "" -f <600 copy>` (fails if encrypted).

## Use in a module

- `link`: read `$env.DOTFILES/configs/secrets/keys/<file>`, guard with `secret-is-plaintext`, skip with a message when
  locked (`configs/core/ntfy/mod.nu`).
- `system`: never reads `keys/`. `dot apply` streams the files in `SYSTEM_SECRETS` (`scripts/lib/system.nu`, plus this
  host's `initramfs-ssh/<hostname>/sshkeydir/.ed25519.sk` and the platform's `wireguard`) to a tmpfs
  `$DOTFILES_SECRETS`; read `$DOTFILES_SECRETS/<path relative to keys/>` (a locked file is absent).
- State a `backup` verb carries back: guard with `secret-seed-guard <marker> <witness> <label>`
  (`configs/gaming/dalamud/mod.nu`), which fails on live state the repo never seeded.

## Add a secret

1. Unlock, put it under `configs/secrets/keys/`. Anywhere else in `configs/secrets/` it is committed in plaintext.
2. A system module needs it: add its path to `SYSTEM_SECRETS`.
3. `dot sync` commits and pushes (submodule first). Agents never do.
4. Never write into `configs/secrets/` while locked: a script checks `secret-is-plaintext` on `pgp_privatekey.asc`
   first and stops.
