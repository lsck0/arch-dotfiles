# base

The system baseline, almost all `system` verbs (root). Root logic that edits live state (crypttab, HOOKS, cmdline, NM
profiles) is a `step`. Subdirs: `apparmor/`, `boot/` have their own AGENTS.md.

- Hardware and host modules return nothing on WSL; their packages are `meta.packages.native`, which WSL skips.
- `pacman`'s system verb runs first so the mirror and key exist before any sync.
- Bypasses are an explicit group or route (`pentest`, `games`), never a loosened global rule.
- `pam`: YubiKey and fingerprint on sudo and polkit, additive to the password; `/etc/u2f_mappings` comes from the
  owner's `configs/secrets/yubikey` module, mapped to the logins in `/var/lib/dotfiles/owners`, never by name.
- `networkmanager`: home detection by gateway MAC (`home_gateways`, secrets, the install answer), the untrusted-network
  persona (`untrusted_policy`), homelab routes and split DNS.
- `xdg`: `app-dirs.conf`, `home.hidden`, `RECLAIM` keep `$HOME` clean.
- `keyboard` (qmk keymap) and `wsl` (`wsl.conf` template) are not modules.
