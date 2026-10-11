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

Anyone else, from the Arch ISO (or a fresh WSL Arch root shell):

```bash
curl -fsSL https://raw.githubusercontent.com/lsck0/arch-dotfiles/master/bootstrap.sh | bash
```

A machine is a `platforms/<name>.sh` or the answers given at install (`/etc/dotfiles/platform.sh`); a user is any
login, with `profiles/<name>.sh` as its profile when there is one, a guest without. Each module has a root
`system.sh`, run once per machine from the root-owned copy `/var/lib/dotfiles/repo`, and a `link.sh` for the user's
home, never with `sudo`. `./install.sh` and `./config.sh` run both for an admin, `--user` only the user's part.

Another login on an installed machine, with its own checkout and user layer:

```bash
adduser-dotfiles <name>
```

## Package groups

A machine installs a layered subset of `configs/<group>/`, chosen by `PKG_GROUPS` in its `platforms/<name>.sh`
(or at install). The layers build on each other: each assumes the ones before it, so a box can stop at any level
and still be coherent — a locked-down headless core, or that core plus a desktop, up to the full workstation.

- **base** — always installed. The secure, stable, performant core: kernel and boot, encryption, the firewall
  and network auto-protection (ProtonVPN on untrusted networks, Tor, anonymous SOCKS), hardening and the
  everyday shell. Everything else is optional on top of this.
- **hardware** — machine-specific improvements and features (sensors, GPU, power/thermal, peripherals).
- **desktop** — the UI (compositor, bar, launcher) plus basic everyday programs: text editing and light
  media manipulation (viewers, players, simple downloaders/torrents).
- **socials** — desktop social-media clients.
- **latex**, **qemu** — typesetting; virtual machines.
- **creating** — heavier creative software: advanced image, video, audio and 3D/CAD editing.
- **gaming** — games and launchers.
- **programming** — development across languages, plus defensive/hardening work that runs locally: fuzzing
  (e.g. `cargo-afl`, `honggfuzz`), static analysis, debuggers, and ordinary dev utilities (a DNS lookup is a
  normal programmer's tool, so it lives here, not in pentesting).
- **llm**, **rocm** — local models and the AMD compute stack they use.
- **pentesting** — tools that *actively act on a target*: scanning, enumeration, exploitation, offensive web
  fuzzing (`ffuf`), C2. Routed through the VPN/Tor layer from **base**.
