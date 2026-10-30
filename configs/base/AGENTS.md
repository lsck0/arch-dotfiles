# base

The system baseline, almost all `system` verbs (root). Root logic that edits live state (crypttab, HOOKS, cmdline, NM
profiles) is a `step`. Subdirs: `apparmor/`, `boot/` have their own AGENTS.md.

- Hardware and host modules return nothing on WSL; their packages are `meta.packages.native`, which WSL skips.
- `pacman`'s system verb runs first so the mirror and key exist before any sync.
- Bypasses are an explicit group or route (`pentest`, `games`), never a loosened global rule.
- `pam`: YubiKey and fingerprint on sudo and polkit, additive to the password; `/etc/u2f_mappings` comes from the
  owner's `configs/secrets/yubikey` module, mapped to the logins in `/var/lib/dotfiles/owners`, never by name.
- `networkmanager`: home detection by gateway MAC (`home_gateways`, secrets, the install answer), the untrusted-network
  persona (`untrusted_policy`), homelab routes and split DNS, the homelab mirror put back first on a home link or
  wg0. `toggle-portal` opens a captive portal window for 120 s on every foreign link (the dispatcher's `<iface>
  portal`), off ends it early.
- `ssh` and `nftables`: sshd listens on `base/ssh.port` behind a three-port knock (`base/ssh.knock`, held open for
  `nftables.ssh_knock_window`); `sshk` and `wake-pc` knock first, 22 is the endlessh tarpit.
- `powercap`: `powercap-watts.service` writes the RAPL package draw as whole watts to `/run/powercap/watts` for the
  bar, `energy_uj` stays root-only; a udev rule starts it once `intel_rapl_msr` loads.
- `xdg`: `app-dirs.conf`, `home.hidden`, `RECLAIM` keep `$HOME` clean.
- Owner rollouts here gate on `profile-has secrets` alone, not `owner-unlocked` (ssh's `ssh-add.service` and
  `authorize`, protonvpn's `auto-vpn`, failure-notify's `recovery-drill`): what they need from the secrets is checked at
  run time (`ssh-add`'s `ExecCondition`, `authorize` appends only readable keys), so they work after an unlock without
  a re-apply. Personal files that point at owner state (the NAS bookmark) gate on `owner-unlocked`.
- `keyboard` (qmk keymap) and `wsl` (`wsl.conf` template) are not modules.
