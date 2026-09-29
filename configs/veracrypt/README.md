# VeraCrypt vault in home

An encrypted vault: a VeraCrypt container at `~/sync/vault.hc` mounted to
`~/vault`. The container sits in `~/sync`, so syncthing carries the ENCRYPTED
blob between devices; the mount point `~/vault` is OUTSIDE `~/sync`, so the
decrypted contents never sync. The password is YOUR secret, never stored.

- `veracrypt-vault.sh`: helper with `create` / `mount` / `umount` / `status`.
- `link.sh`: symlinks it to `~/.local/bin/veracrypt-vault`, and creates the
  container on first run when a terminal is present (the password prompt cannot
  run in the non-interactive install link loop). No TTY, no container: it prints
  the `create` command to run later.

Caveat: since the container syncs, do not mount it on two machines at once (two
writers make a sync conflict on the blob).

## Install

`veracrypt` is in `[base]` of `install.sh` (extra repo):

```
sudo pacman -S veracrypt   # or: yay -S veracrypt
```

## 1. One-time: create the vault (you choose the password)

`install.sh` runs this for you on first setup when a terminal is present.
VeraCrypt prompts for the password on its own: it is never passed on the CLI,
echoed, or stored anywhere. Refuses to run if `~/sync/vault.hc` already exists.

```
veracrypt-vault create        # 1G default
veracrypt-vault create 5G     # or a custom size
```

## 2. Daily use: mount / dismount

```
veracrypt-vault mount     # prompts for password, mounts at ~/vault
veracrypt-vault umount    # dismounts ~/vault
veracrypt-vault status    # list mounted volumes
```

## SECURITY

This repo is PUBLIC. The container `~/sync/vault.hc` and the mountpoint `~/vault`
live in `$HOME`, NOT in the repo, and must NEVER be committed. The password is
never written to disk by this tooling. `.gitignore` here and the root
`.gitignore` block `*.hc` / `Vault/` as belt-and-suspenders.
