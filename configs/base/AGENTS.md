# base

The system baseline, almost all `system` verbs (root). Root logic that edits live state (crypttab, HOOKS, cmdline, NM
profiles) is a `step`. Subdirs: `apparmor/`, `boot/` have their own AGENTS.md.

- Hardware and host modules return nothing on WSL: `meta.native_only: [system]` (the verbs the engine skips there), or
  a guard in the verb when WSL is one condition of several; their packages are `meta.packages.native`, which WSL skips.
- `pacman`'s system verb runs first so the mirror and key exist before any sync.
- Bypasses are an explicit group or route (`pentest`, `vpn-bypass`, `vmnet` for vm-net's DoT to quad9 only), never a
  loosened global rule.
- `pam`: YubiKey and fingerprint on sudo and polkit, additive to the password; `/etc/u2f_mappings` comes from the
  owner's `configs/secrets/yubikey` module, mapped to the logins in `/var/lib/dotfiles/owners`, never by name. sudo's
  stack opens with a terminal gate (`TTY_LINE`): a process without a terminal gets no factor at all, so an agent's
  tool shell cannot raise a touch request nobody sees; one that allocates a pty (`script`, a multiplexer pane) passes.
  `sudo`'s `05-timestamp` pins the per-terminal cache (15 min). `faillock.conf` (6 failures, 120 s) is one tally for
  sudo, polkit, the lock screen and ly; the lock screen's fingerprint service exists only where `has-fprint`.
- `networkmanager`: two tiers by gateway MAC. Home (`home_gateways`, secrets, the install answer) is the homelab's
  network: homelab routes and split DNS, the homelab mirror put back first, the NAS, printers; NM's connectivity
  probe resolves through the lab DNS. A home line is `<mac> <gateway address> <dhcp server identifier>` and needs all
  three (the MACs were public once); a MAC alone only counts as trusted, and not at all once a full line names it.
  Trusted (`trusted_gateways`, secrets' `keys/trusted-gateways` where `toggle-trust-network` writes while unlocked,
  plus home) only lifts the untrusted-network persona (`untrusted_policy`, whose `off` trusts every routed link):
  `/run/trusted-network` feeds the firewall's `trusted_links` sets, tor-router and the persona; `/run/home-network`
  the homelab wiring. The homelab mirror also comes back first on wg0. `toggle-portal` opens a captive portal window
  for `portal_window_s` (default 300) on every foreign link (the dispatcher's `<iface> portal`), off ends it early.
  The MAC is one per network and boot (`connection.stable-id`), never the hardware one.
- `ssh` and `nftables`: sshd listens on `base/ssh.port` behind a three-port knock (`base/ssh.knock`, held open for
  `base/nftables.ssh_knock_window`); `sshk` and `wake-pc` knock first, 22 is the endlessh tarpit. `wake-pc` and
  programming/offload wake and reach the desktop through one library, `ssh/scripts/wake.nu` (`host-wake`). New
  connections to the port are rate-limited per source (`base/nftables.ssh_rate`); `fail2ban` is off on luca-pc and
  luca-notebook, where that limit stands in for it. tun0 reaches the pentest listener ports only with
  `base/nftables.pentest_listeners`. Host keys are pinned from `keys/ssh-host/<host>/` (`SSH_HOST_KEYS`), so a
  reinstall keeps the identity; without them sshd generates its own and the apply prints the backup command.
- `nftables` fw-egress: under lockdown-tor it fails closed whether tor is there or not; besides tor only pacman's
  download user (tcp 80/443) and resolved (DoT on 853) get out, so a machine without tor can still install it. Once
  tor-router is up everything, those two included, reaches it redirected to loopback with oifname still the uplink,
  so fw-egress accepts loopback by address (`base/tor/tor-router.test.nu` runs both rulesets). The uids are looked up
  at unit start, so nftables never waits on base/tor (lint: `FAIL_CLOSED` in `scripts/lib/gate.nu`).
- `powercap`: `powercap-watts.service` writes the RAPL package draw as whole watts to `/run/powercap/watts` for the
  bar, `energy_uj` stays root-only; a udev rule starts it once `intel_rapl_msr` loads.
- `xdg`: the `$HOME` rules are the root `AGENTS.md`'s. A `RECLAIM` row names the file that shows its tool is installed
  (`program`, also a `meta.inputs` entry); its link and target dir wait for that file, so a machine without the tool
  keeps no link in `$HOME`. It also owns the user applications dir's `mimeinfo.cache`, rebuilt when an entry there is
  newer.
- Owner rollouts here gate on `profile-has secrets` alone, not `owner-unlocked` (ssh's `ssh-add.service` and
  `authorize`, protonvpn's `auto-vpn`, failure-notify's `recovery-drill`): what they need from the secrets is checked at
  run time (`ssh-add`'s `ExecCondition`, `authorize` appends only readable keys), so they work after an unlock without
  a re-apply. Personal files that point at owner state (the NAS bookmark) gate on `owner-unlocked`.
- `keyboard` (qmk keymap) and `wsl` (`wsl.conf` template) are not modules.
