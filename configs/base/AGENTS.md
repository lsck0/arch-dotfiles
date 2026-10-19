# base

Extends the root `AGENTS.md`. The system baseline present on every machine: boot, security, networking,
power, hardware and the package layer. Almost all of it is a `mod.nu` `system` verb (root); few have a `link` verb.
Root logic that reads or edits live state (crypttab, mkinitcpio HOOKS, the kernel cmdline, NM profiles) is a `step`:
one of the module's own exported commands, run at apply time.

## Modules

- `apparmor`: AppArmor confinement policy and the own/local profiles. See `apparmor/AGENTS.md`.
- `boot`: UKI, secure boot (sbctl), luks, remote-unlock, the boot barrier. See `boot/AGENTS.md`.
- `cleanup`: journald size cap and periodic pacman cache/orphan cleanup.
- `coredump`: systemd-coredump storage, age and size limits.
- `dot`: dot's own wiring: the zsh and nushell completions (`dot internal completions`) and the polkit action
  `system-apply.nu` runs under (`dev.lsck0.dotfiles.policy`, auth_admin every time).
- `endlessh`: ssh tarpit holding scanners on a decoy port.
- `essentials`: the base system and the shared libraries and tools no one module owns (packages only).
- `fail2ban`: ban hosts after repeated auth failures.
- `failure-notify`: notify through the journal to each admin when a systemd unit fails; monthly lynis audit.
- `fancontrol`: fan curve fitted to this board and its 9950X3D.
- `fprintd`: fingerprint auth; python-validity for validity/synaptics sensors only.
- `fwupd`: firmware updates.
- `ghostmirror`: rank and rebuild the pacman mirrorlist (weekly sort, monthly rebuild).
- `hardening`: host sysctl and kernel hardening keys.
- `hardware`: firmware, gpu drivers and hardware diagnostics (native packages only).
- `i2c`: i2c-dev for ddc monitor control.
- `keyboard`: the sofle choc qmk keymap and its build (not a module).
- `lact`: AMD GPU control daemon.
- `networkmanager`: NM config, the dispatchers (home rule, homelab routes, the untrusted-network persona); options
  `untrusted_policy`, `home_wired`, `home_gateways`, `homelab_*` (written to `/etc/NetworkManager/homelab.env`).
- `nftables`: the egress firewall.
- `oomd`: systemd-oomd plus the oom-notify hook.
- `ossec`: host IDS; its alert log feeds the quickshell system panel.
- `pacman`: pacman.conf, makepkg.conf, root hooks, the `[lsck0]` mirror and key.
- `pam`: fingerprint and YubiKey auth on sudo and polkit, additive to the password.
- `perf`: I/O scheduler tuning and perf_event access.
- `plymouth`: boot splash.
- `portmaster`: the application firewall; global rules and the per-connection/dns bypass (see `pentesting`, `gaming`).
- `powercap`: RAPL power limits.
- `protonvpn`: ProtonVPN client, only for an identity with an account.
- `protonvpn-netns`: a netns whose only route is a proton wireguard tunnel; ani-cli, yt-dlp, streaming mpv run inside.
- `resolved`: systemd-resolved, DoT (Quad9) off-VPN, homelab/VPN split-DNS.
- `sandbox`: systemd-native sandboxes, `sandbox-build` (untrusted builds) and `confine` (GUI-safe scope).
- `scx`: sched_ext schedulers (laptop uses scx_lavd).
- `smartd`: SMART disk health; skips itself in a vm.
- `ssh`: sshd and client config.
- `sudo`: sudoers policy, validated before install so a broken drop-in cannot lock admins out.
- `systemd`: system-wide systemd and socket defaults.
- `tablet`: T1161 drawing tablet udev rules and userspace driver.
- `tlp`: laptop power management and epp.
- `tor`: tor daemon.
- `v4l-utils`: video4linux utilities.
- `v4l2loopback`: virtual camera kernel module.
- `wireguard`: wireguard tooling; the tunnel config lives in the admin's secrets, brought up by `toggle-vpn.nu`.
- `wsl`: the wsl.conf bootstrap.sh writes (not a module).
- `xdg`: XDG base dirs, `app-dirs.conf`, `home.hidden`, `RECLAIM` in `mod.nu` (the `$HOME`-clean machinery; see root).
- `yubikey`: card and FIDO access for every admin.
- `zram`: compressed swap sized so a build cannot evict the desktop's hot pages before oomd reacts.

## Conventions

- Hardware and host-level modules declare nothing under WSL (`if $env.FORM_FACTOR? == "wsl" { return [] }`); their
  packages sit in `meta.packages.native`, which WSL skips: Windows owns the kernel, boot, drivers, power, audio and
  network there.
- Order matters at the package layer: `pacman`'s system verb runs before any sync so the mirror and key exist first.
- Policy lives in `profiles.conf` (AppArmor) and in `nftables`/`portmaster`; a bypass is an explicit group or route,
  never a loosened global rule.
