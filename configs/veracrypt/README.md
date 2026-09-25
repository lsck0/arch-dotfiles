# VeraCrypt vault in home

An encrypted "vault in home": a VeraCrypt container at `~/Vault.hc` mounted to
`~/Vault`. The encryption password is YOUR secret and the container is created
interactively, so this repo ships only the tooling + docs. You run the one-time
`create` step yourself, like the manual auth steps in `configs/proton/`.

- `veracrypt-vault.sh` — helper with `create` / `mount` / `umount` / `status`.
- `link.sh` — symlinks it to `~/.local/bin/veracrypt-vault` (run by top-level `install.sh`).

## Install

`veracrypt` is in `[base]` of `install.sh` (extra repo):

```
sudo pacman -S veracrypt   # or: yay -S veracrypt
```

## 1. One-time: create the vault (manual, you choose the password)

VeraCrypt prompts for the password on its own — it is never passed on the CLI,
echoed, or stored anywhere. Refuses to run if `~/Vault.hc` already exists.

```
veracrypt-vault create        # 2G default
veracrypt-vault create 5G     # or a custom size
```

## 2. Daily use: mount / dismount

```
veracrypt-vault mount     # prompts for password, mounts at ~/Vault
veracrypt-vault umount    # dismounts ~/Vault
veracrypt-vault status    # list mounted volumes
```

## SECURITY

This repo is PUBLIC. The container `~/Vault.hc` and the mountpoint `~/Vault`
live in `$HOME`, NOT in the repo, and must NEVER be committed. The password is
never written to disk by this tooling. `.gitignore` here and the root
`.gitignore` block `*.hc` / `Vault/` as belt-and-suspenders.
