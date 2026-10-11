<div align="center">
  <h1>Arch Dotfiles</h1>
</div>

![media, weather and network panels](showcase/showcase1.png)
![media, weather and network panels](showcase/showcase2.png)
![wallpaper picker](showcase/showcase3.png)
![clock, system and app launcher](showcase/showcase4.png)

```bash
curl -fsSL https://install-{pc, notebook, wsl}.lsck0.dev | sh
```

Anyone else, from the Arch ISO (or a fresh WSL Arch root shell); it asks for the machine instead of reading a
`platforms/` file:

```bash
curl -fsSL https://install-generic.lsck0.dev | sh
```

A machine is a `platforms/<name>.sh` or the answers given at install (`/etc/dotfiles/platform.sh`); a user is any
login, with `profiles/<name>.sh` as its profile when there is one, a guest without. A profile's capabilities turn on
what only the owner has: `secrets` (the YubiKey unlock), `identity` (git/gpg/ssh/pass), `homelab` (nas, ntfy,
syncthing) and `work` (the isolated capgemini chromium profile). Each module has a root
`system.sh`, run once per machine from the root-owned copy `/var/lib/dotfiles/repo`, and a `link.sh` for the user's
home, never with `sudo`. `./install.sh` and `./config.sh` run both for an admin, `--user` only the user's part.

Another login on an installed machine, with its own checkout and user layer:

```bash
adduser-dotfiles <name>
```

## Package groups

A machine installs a layered subset of `configs/<group>/`, chosen by `PKG_GROUPS` in its `platforms/<name>.sh`
(or at install). The layers build on each other: each assumes the ones before it, so a box can stop at any level
and still be coherent — a locked-down headless base, or that plus the everyday shell, up to the full workstation.

- **base** — always installed. Everything for a secure, stable, performant machine with no user-facing features:
  kernel and boot (systemd-boot, UKI, Secure Boot, plymouth), hardening and apparmor, performance (scx, zram, oomd,
  perf, powercap, tlp), disk encryption, the whole network stack and auto-protection (NetworkManager, nftables,
  portmaster, fail2ban, endlessh, ossec, ProtonVPN on untrusted networks, WireGuard, Tor, resolved/DoT), the
  mirror ranker, pacman, sudo, pam, the YubiKey system side, systemd, coredump, cleanup, timeshift, failure and
  update notifications, and all the machine-specific hardware (firmware, drivers, fwupd, smartd, sensors/fancontrol,
  lact, i2c, keyboard firmware, tablet, v4l2loopback). The hardware-only packages live in `base/packages.native.txt`, installed on every form factor
  but wsl, where Windows owns the kernel, boot, drivers, power, audio and network.
- **core** — the everyday user shell and CLI: zsh/starship/tmux/nushell, XDG dirs, NAS, locale, timezone, GPG,
  git, gh, the ssh/herdr setup, theming (wallust, shared with desktop), toggles, trash, yazi, btop, fastfetch,
  borg, syncthing, ntfy, proton, yt-dlp, and the CLI diagnostics (journal TUIs, DNS/network lookups, coreutils-like
  tools, archivers). Runs before desktop, so its theming is in place first.
- **desktop** — the UI (compositor, bar, launcher) plus the user-facing hardware and programs: audio (pipewire),
  printing and scanning (cups, sane), bluetooth UI, browsers, terminals, document and media viewers/editors,
  thunderbird, torrents.
- **socials** — desktop social-media clients.
- **latex**, **qemu** — typesetting; virtual machines.
- **creating** — heavier creative software: advanced image, video, audio and 3D/CAD editing, OBS.
- **gaming** — games and launchers.
- **programming** — development across languages, plus defensive/hardening work that runs locally: fuzzing
  (e.g. `cargo-afl`, `honggfuzz`), static analysis, secret scanners, debuggers, and ordinary dev utilities (a DNS
  lookup is a normal programmer's tool, so it lives here, not in pentesting).
- **llm**, **rocm** — local models and the AMD compute stack they use.
- **pentesting** — tools that *actively act on a target*: scanning, enumeration, exploitation, offensive web
  fuzzing (`ffuf`), C2. Routed through the VPN/Tor layer from **base**; `pentest <command>` runs one past
  portmaster's per-connection queue and dns interception.
