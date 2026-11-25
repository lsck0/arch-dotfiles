# Features

Everything here is set up by the install (bootstrap, then `dot apply`) and kept current by `dot sync`.
`dot plan --modules`, `dot set` and `hyprctl binds` list modules, options and keybinds. SUPER is the mod key.

## dot

- `dot sync`: pull (signature-verified), migrate, install, apply, back up app state, signed `Generation: <n>` commit
  behind the formatter, linter and gitleaks gates, push.
- `dot apply`, `dot plan`, `dot status`, `dot set`, `dot theme`, `dot module adopt|reset|unlink|remove|restore`,
  `dot explain`, `dot log`, `dot secrets`, `dot test lint|check|fmt|run`: see `dot --help`.
- Platforms `luca-pc`, `luca-notebook`, `server`, `vm`, `wsl` or `custom` (answered at install); profile `luca`
  (owner, with secrets) or `custom` (no capabilities).
- Install: the lsck0 iso (answer file optional) or `curl | sh` from the official Arch ISO or WSL.
- `[lsck0]` package mirror built by the homelab from `mirror/`.

## Security

- AppArmor (apparmor.d plus own profiles, content openers enforced; `aa enforce|complain|off <profile>` per machine),
  KSPP cmdline, sysctl hardening, a modprobe blacklist.
- LUKS root: TPM2+PIN, YubiKey FIDO2 or passphrase; remote unlock over initramfs ssh; secure boot with own keys, UKIs;
  `dot sync` backs the header up into the secrets every 90 days.
- sudo and polkit: YubiKey touch or fingerprint (fprintd), password fallback; sudo refuses a caller without a terminal;
  faillock locks for two minutes after six failures.
- nftables lockdown by default, inbound opens on home networks, port-knocked sshd (host keys pinned across
  reinstalls); with `untrusted_policy` lockdown-tor (luca-pc, luca-notebook) an egress kill switch off home.
- A per-source rate limit on the ssh port (fail2ban where a platform keeps it on), an endlessh tarpit on port 22, a
  Wazuh agent reporting journal, file integrity, rootcheck and the CIS Arch policy to the homelab's manager.
- Untrusted networks: a MAC per network and boot, Avahi masked (IPv6 off too under lockdown-tor), ProtonVPN or tor;
  fail-closed VPN namespace for `vpn <cmd>`; Steam and its games bypass ProtonVPN as group `vpn-bypass` after a key
  touch; Portmaster.
- DNS over TLS to Quad9 with DNSSEC, LLMNR and mDNS off (systemd-resolved).
- Audit timers (lynis, arch-audit, update and doctor checks, recovery drill); a failed unit notifies, and the login
  shows what the last run left in `FAILURES.*`.
- Secrets in a git-crypt submodule unlocked with the YubiKey, `dot secrets audit` for what is due for rotation or a
  recovery drill; a secrets commit refuses a file that would land unencrypted; per-repo credential isolation
  (`identity-init`).
- Telemetry off everywhere but Claude Code where `remote_control` is on; browser policies; sandboxed builds
  (`sandbox-build`), confined GUI apps (`confine`).

## Desktop

- Hyprland (Lua config; the dynamic-cursors plugin, built per Hyprland commit), uwsm, ly; Plasma as a second session.
- quickshell: bar with clock, weather, media, OBS, Discord, agents, homelab, system, network, display, audio and
  notification panels; launcher, clipboard (with OpenPGP), settings window, tasks and notes, overview, power menu, lock,
  OSD, reminders, pomodoro, desktop agenda (sections now, all day, meetings, to do) with the quote of the day set on
  the wallpaper, or the wallpaper's own (`wallpapers/quotes.json`).
- Toggles (`scripts/toggles/`; `prefix+m` in tmux and herdr, the bar, the settings window on `SUPER+comma`): route
  (direct, proton, tor, offline), homelab VPN, firewall, captive portal, radios, focus, night light, shaders, color
  grading, power mode, font, theme mode and more; a failure is one toast with its cause.
- Theming: 74 palettes or wallust from the wallpaper, applied live to every themed app (`dot theme`; pickers on
  `SUPER+CTRL+w` for wallpapers, `SUPER+SHIFT+w` for themes, with the recent picks and a lottery, `CTRL+R` for a
  wallpaper, `CTRL+T` for a theme).
- Idle: dim, lock, screens off, suspend, each sooner in power saver; guards for media, a recording microphone, ssh and
  working agents. Lid closed with an external monitor moves the desktop there.
- Power and disks: tlp, zram, the sched_ext lavd scheduler on laptops, smartd, the CPU package's draw in the bar.
- Shimeji desktop mascots.

## Apps

- Shell: zsh and nushell, starship, tmux and herdr, ghostty, yazi, about 60 CLI tools.
- Editors: Neovim (LSPs for about 40 languages via mason), Emacs, VSCodium, Zed, JetBrains.
- Agents: Claude Code, Copilot, Gemini, Hermes, sharing `skills/`; MCP servers registered per app.
- Toolchains for C, Rust, Go, Zig, Odin, Haskell, OCaml, Lean, Jai, Python, Java, .NET, Node, Typst, Android; nix,
  devenv, docker, podman, kubernetes, PostgreSQL; Forgejo (`tea`) and Grafana MCP for the homelab.
- Formal verification (cbmc, TLA+, z3, kani, flux) and debuggers (gdb, cgdb, nnd, raddbg, RenderDoc).
- Mail (Thunderbird, Proton Mail), LibreOffice, zathura, sioyek, Obsidian, VeraCrypt; mpv, nsxiv, qBittorrent,
  JDownloader; KDE Connect as the phone link.
- Browsers: Firefox, Chromium, qutebrowser, Tor Browser. Chat: Signal, Telegram, Element, Discord, TeamSpeak. Spotify
  (spicetify).
- Homelab: ntfy pushes to the desktop, alloy ships metrics and the journal to its Grafana.
- Taskwarrior with the homelab sync server, timewarrior, bugwarrior; homelab calendar on the desktop agenda.
- LLMs: ollama and vLLM (ROCm), socket activated, models pinned (ollama's by digest, vLLM's by commit; abliterated
  chat models, an embedding and a coding model), and only those (ollama drops any other model); ollama splits a model
  too big for the GPU into RAM;
  Alpaca as a desktop client.
- Generation: ComfyUI (Flux schnell, Hunyuan3D 2.1) behind `comfy-gen` and Blender's Generate sidebar.
- Gaming: Steam, Proton, gamemode, MangoHud, FFXIV with Dalamud, Lutris, Diablo II (vanilla, Median XL, PD2 S3 and
  S14), Path of Exile (Path of Building, Awakened PoE Trade), Path of Exile 2 (Exiled Exchange 2), Minecraft, VR,
  emulators (RetroArch, melonDS, mGBA), NetHack, Heroic; Proton-GE, vkBasalt.
- Creating: OBS (streaming, recording, virtual cam), Blender, GIMP, Krita, Inkscape, kdenlive, Audacity, OpenSCAD,
  Godot, Unreal; MCP servers for OBS, Blender, Inkscape, Audacity, OpenSCAD, Godot and Unreal.
- LaTeX, Zotero; libvirt, Waydroid, distrobox, qemu-user for foreign architectures; a pentesting toolkit.

## Workflows

- Capture: `SUPER+i` opens the launcher on a new task, `SUPER+SHIFT+i` on a reminder. In the launcher, a leading `+`
  adds a task (taskwarrior syntax: `+ Dino letter project:dino scheduled:mon due:fri priority:H +uni`), `!` sets a
  reminder (`! 10m tea`, `! 1h30m stretch`, `! 15:00 dentist`; the row shows when it fires, the pending ones below it,
  `DEL` cancels one), `#` appends a timestamped line to `~/sync/notes/inbox.md`. The same from a shell: `capture
  task|remind|note <words>`. A rejected task reopens the launcher on the typed line. `>` runs a shell
  command (`SHIFT+ENTER` in kitty), notifies when it fails and lists recent commands; `=` calculates, `@` finds a
  window, `:` searches the clipboard, `?` the keybinds; `CTRL+V` pastes.
- Tasks: `scheduled:` is when a task can start, `due:` its deadline (`due:eod` ends the day; `due:tomorrow` is its
  first minute), `priority:H|M|L`, `wait:` hides it until then. The agenda's to-do rows show priority in the marker
  (`!` overdue), a pending start as `@14:00`, `@Tue` or `@Nov 20`, then the time left until due. `SUPER+o` for the full
  panel, sorted overdue first, then by urgency like `task next`: `e` edits a task, `u` undoes the last done, delete,
  start or stop, and a rejected add or edit stays in the line with its error. An outside change (capture, sync, the
  CLI) shows within a second.
- Notes: plain markdown in `~/sync/notes`, synced. `SUPER+ALT+n` opens nvim there on the inbox; `SUPER+SHIFT+n` is the
  scratch pad (also the desktop's notes card, and the panel's notes tab; its inbox tab shows the `#` notes). A
  scratch-pad edit that clashes with a change on disk is kept as `notes.conflict-<time>.md` when the panel closes.
- Textures and meshes: `comfy-gen texture <prompt>` writes a seamless set (albedo, normal, roughness, height) to
  `~/pictures/comfyui/textures/<name>/`; `comfy-gen 3d <image|prompt> [--open]` a `.glb` mesh (shape only, no
  texture); `comfy-gen image <prompt>`; `--json` for scripts and agents. In Blender, the N sidebar's Generate tab
  textures the selected meshes from a prompt (box projected, no UVs needed) or imports a generated mesh. The first run
  after idle loads the model; a texture takes under a minute, a mesh a few.

## Backups

- Config in git; app state in the secrets submodule (`keys/` encrypted, `state/` plain), backed up by `dot sync`;
  Proton sign-ins carried across a reinstall.
- `~/sync` via syncthing with the NAS; NAS share at `/mnt/homelab`.

## Keybinds

Keys are SUPER plus the named key unless written as a full chord; `hyprctl binds` prints every bind with its
description.

- Apps: terminal (`Return`, kitty on `SHIFT+Return`), Firefox (`a`), qutebrowser (`SHIFT+a`), file manager (`e`),
  editor (`n`), notes pad (`SHIFT+n`), notes folder (`ALT+n`), system monitor (`SHIFT+t`), magnifier (`x`), desktop
  mascots (`y`, `SHIFT+y` stops them).
- Shell: launcher (`d`, `ALT+d` runs from `$PATH`), dismiss notifications (`SHIFT+d`), quick capture (`i`, `SHIFT+i`
  a reminder), dictation (`ALT+v`, again to type it), clipboard (`v`), overview (`Tab`; while open `Tab` and
  `SHIFT+Tab` step, `Return` goes there, `Escape` without SUPER closes), tasks (`o`), settings (`comma`), timer
  (`t`), wallpaper picker (`CTRL+w`), theme picker (`SHIFT+w`), power menu (`SHIFT+e`), lock (`Escape`), restart
  quickshell (`SHIFT+r`), discord mute (`m`), clipboard to the phone (`u`, `SHIFT+u` shares files, a link or text),
  system agent with `hermes.system_agent` (`grave`, the key under Escape, shows it; `ALT+a` talks).
- Bar panels: `b` then a letter: `a` audio, `b` notifications, `c` clock, `d` display, `h` homelab, `i` agents, `m`
  media, `n` network, `o` obs, `s` system, `v` discord voice, `w` weather.
- Windows: focus and move (`hjkl` or arrows, `SHIFT` moves), both walking through a tab group as in i3 (focus cycles
  its tabs before leaving, a move enters and leaves it), close (`q`), float (`space`), fullscreen (`f`), previous
  window (`s`), split (`g`), tabs (`w` tabs or untabs the window, `CTRL+hjkl` tabs it with that neighbour, `c` and
  `SHIFT+c` next and previous tab, `SHIFT+h`/`l` reorder a tab before leaving the group; a titled tab bar), resize
  mode (`r`), mouse move and resize.
- Workspaces: `1` to `0` focus, `SHIFT` moves the window there.
- Capture: a region (`Print` alone or `SHIFT+s`), the monitor (`SHIFT+Print` without SUPER), the window (`Print` with
  SUPER), each saved to `~/pictures/screenshots` and copied; screen recording (`ALT+Print` starts and stops, into
  `~/videos/recordings`), color picker (`p`), OBS replay buffer (`F9` saves, `SHIFT+F9` starts or stops), MangoHud
  (`SHIFT+F12` without SUPER).
- Media and hardware keys, also on the lock screen: playback (the bar's player), volume, mic mute, brightness (`SHIFT`
  for software brightness), keyboard backlight (`SHIFT+b`), lid switch; `F13` is TeamSpeak's push-to-talk.

## Modules

Every module under `configs/`, the owner's own in `configs/secrets/` aside. A platform runs the groups it lists.

<!-- modules: generated by dot internal gen from configs/ -->
| group | modules |
|---|---|
| `base` | `apparmor`, `boot/hardening`, `boot/luks`, `boot/remote-unlock`, `boot/sata`, `boot/sbctl`, `boot/systemd-boot`, `bootvine`, `cleanup`, `coredump`, `dot`, `endlessh`, `essentials`, `fail2ban`, `failure-notify`, `fancontrol`, `fprintd`, `fwupd`, `ghostmirror`, `hardening`, `hardware`, `i2c`, `lact`, `networkmanager`, `nftables`, `oomd`, `pacman`, `pam`, `perf`, `portmaster`, `powercap`, `protonvpn`, `protonvpn-netns`, `resolved`, `sandbox`, `scx`, `smartd`, `ssh`, `sudo`, `systemd`, `tablet`, `tlp`, `tor`, `v4l-utils`, `v4l2loopback`, `wazuh`, `wireguard`, `xdg`, `yubikey`, `zram` |
| `core` | `alloy`, `btop`, `cli`, `fastfetch`, `gh`, `git`, `gnupg`, `herdr`, `locale`, `nas`, `ntfy`, `nushell`, `proton/pass`, `proton/sessions`, `starship`, `syncthing`, `timezone-auto`, `tmux`, `toggles`, `trash`, `veracrypt`, `wallust`, `yazi`, `yt-dlp`, `zsh` |
| `creating` | `apps`, `audacity`, `blender`, `gimp`, `inkscape`, `krita`, `obs`, `openscad` |
| `desktop` | `applications`, `bookokrat`, `chromium`, `color-grading`, `cursor`, `dictation`, `feather`, `firefox`, `ghostty`, `gparted`, `gtk`, `hyprland`, `idle-guards`, `jdownloader`, `kdeconnect`, `kitty`, `libreoffice`, `ly`, `mpv`, `nsxiv`, `obsidian`, `oomox`, `pipewire`, `plasma`, `printing`, `qbittorrent`, `quickshell`, `qutebrowser`, `shimoji`, `thunderbird`, `uwsm`, `zathura` |
| `fonts` | `fonts` |
| `gaming` | `awakened-poe-trade`, `d2launcher`, `dalamud`, `emulators`, `exiled-exchange-2`, `ffxiv`, `gamemode`, `games`, `lutris`, `mangohud`, `modrinth`, `nethack`, `pd2`, `protonup`, `runtime`, `steam`, `vkbasalt`, `vpn-bypass`, `vr` |
| `latex` | `latex`, `sioyek`, `zotero` |
| `llm` | `alpaca`, `comfyui`, `ollama`, `tools`, `vllm` |
| `pentesting` | `caido`, `ghidra`, `llm-jailbreaks`, `metasploit`, `netscanner`, `nuclei`, `pentest`, `proxychains`, `rustscan`, `seclists`, `toolkit`, `wireshark`, `zaproxy` |
| `programming` | `act`, `agent-rules`, `android`, `arduboy`, `asm-lsp`, `bruno`, `bugwarrior`, `cargo`, `caveman`, `cgdb`, `claude`, `copilot`, `debugging`, `devtools`, `direnv`, `docker`, `elan`, `emacs`, `espressif`, `flux`, `forgejo`, `formatting`, `gdb`, `gemini-cli`, `gh-dash`, `ghcup`, `godot`, `grafana`, `hermes`, `http`, `infra`, `jai`, `jetbrains`, `kani`, `kubernetes`, `lazygit`, `math`, `nietzschian`, `nix`, `nnd`, `nvim`, `offload`, `opam`, `playwright`, `postgres`, `projects`, `python`, `registry`, `renderdoc`, `rtk`, `security`, `task`, `toolchains`, `trmnl-claude`, `typos`, `unreal`, `vcs`, `verification`, `vscode`, `web-mcp`, `zed` |
| `qemu` | `binfmt`, `containers`, `libvirt`, `waydroid` |
| `rocm` | `compute` |
| `socials` | `apps`, `desktop`, `discord`, `element`, `fluxer`, `spotify`, `teamspeak`, `telegram` |
<!-- modules end -->

## Options

Every typed option besides `enable`. Detected: set from the hardware when the platform and profile leave it unset.

<!-- options: generated by dot internal gen from each module's options -->
| option | type | default | what it does |
|---|---|---|---|
| `base/boot/hardening.allow_smt` | `bool` | `false` | Keep hyperthreading despite MDS/MMIO, accepting the cross-sibling leak for the threads |
| `base/boot/hardening.relax_mitigations` | `bool` | `false` | Trade kernel hardening for speed on an old Intel cpu: retbleed=stuff for IBRS, no page zeroing on alloc and free, a lazy iommu; a Kaby Lake laptop paid 1.4 us per syscall and faulted fresh memory at 1 GB/s |
| `base/boot/remote-unlock.ssh_unlock` | `bool` | `false` | Wake-on-lan this machine, then ssh into the initramfs to unlock LUKS remotely |
| `base/boot/remote-unlock.wifi` | `bool` | `false` | Also join the home wifis (configs/secrets/keys/wifi) in the initramfs; their keys are written into the image |
| `base/boot/sata.probe` | `bool` | `true` | Probe the SATA ports at boot; false on a machine without SATA disks keeps the built-in AHCI driver from loading (0.3 s per empty port with staggered spin-up), and a SATA disk added later stays invisible until this is true again |
| `base/boot/systemd-boot.menu_timeout_s` | `int` | `0` | Seconds the boot menu waits before the default entry; 0 hides it, a held key still shows it |
| `base/cleanup.journal_max_use` | `string` | `"1G"` | Total disk space the systemd journal may keep, journald.conf(5) size syntax |
| `base/cleanup.journal_retention` | `string` | `"3month"` | Age past which journal entries are dropped even with space left, journald.conf(5) MaxRetentionSec |
| `base/cleanup.nix_gc_days` | `int` | `30` | Age in days past which the weekly nix-gc deletes old generations |
| `base/coredump.max_use` | `string` | `"256M"` | Total disk space systemd-coredump may keep across every stored core, systemd.coredump(5) size syntax |
| `base/coredump.process_size_max` | `string` | `"1G"` | Largest process core systemd-coredump will process at all, above it the core is skipped entirely |
| `base/coredump.external_size_max` | `string` | `"1G"` | Largest core systemd-coredump will write to storage, independent of the process size limit |
| `base/coredump.retention` | `string` | `"7d"` | Age past which stored cores are deleted, tmpfiles.d(5) age syntax |
| `base/fail2ban.bantime` | `int` | `3600` | Seconds an IP stays banned after too many failed attempts, fail2ban jail.conf(5) bantime |
| `base/fail2ban.findtime` | `int` | `600` | Seconds of history fail2ban scans for failed attempts, fail2ban jail.conf(5) findtime |
| `base/fail2ban.maxretry` | `int` | `5` | Failed attempts within findtime before an IP is banned, fail2ban jail.conf(5) maxretry |
| `base/ghostmirror.homelab_mirror` | `string?` | `"http://10.100.0.100:8090/archlinux/$repo/os/$arch"` | A homelab pacman mirror's URL ($repo and $arch as in a mirrorlist), put first on a homelab machine; default the lab's |
| `base/ghostmirror.mirror_countries` | `list<string>?` | unset | Countries the monthly rebuild ranks mirrors from, as ghostmirror -c names them (Germany, "United States"); unset, the ones the install ranked, else Central Europe |
| `base/hardware.nvidia_driver` | `string?` | detected | NVIDIA driver branch: open (Turing on), 580xx (Maxwell to Volta), 470xx (Kepler), none (nouveau) |
| `base/networkmanager.untrusted_policy` | `string` | `"firewall-only"` | On an untrusted network: lockdown-tor closes inbound and lets out only tor, dhcp and tunnels until a VPN is up; firewall-only closes inbound and leaves egress open; off treats every network as trusted |
| `base/networkmanager.portal_window_s` | `int` | `300` | Seconds toggle-portal leaves a foreign link open for a captive portal's sign-in before the lockdown is back |
| `base/networkmanager.home_wired` | `bool?` | detected | Ethernet keeps its hardware MAC and IPv6, so a home gateway can vouch for it (a desktop); null detects it from the form factor |
| `base/networkmanager.wake_on_lan` | `bool` | `false` | Wake on a magic packet over ethernet (udev sets it on every wired link, NetworkManager leaves it) |
| `base/networkmanager.wifi_radio` | `bool?` | detected | Wi-Fi radio on at first boot; off on a desktop wired to the network, so only the link in use is up. Later toggles (toggle-wifi) persist in NetworkManager's own state; null detects it |
| `base/networkmanager.connectivity_check` | `bool` | `true` | Probe ping.archlinux.org over http every 10 minutes for internet and captive portals; off sends nothing |
| `base/networkmanager.home_gateways` | `list<string>` | `[]` | The home network's routers, the one with the homelab (its dns, routes, mirror, nas, printers), each '<mac> <gateway address> <dhcp server identifier>' (a mac alone is only trusted), beside the admin's configs/secrets/keys/home-gateways; home is trusted too |
| `base/networkmanager.trusted_gateways` | `list<string>` | `[]` | Router MACs of trusted networks: no lockdown, direct egress, the lan's inbound services, the hardware MAC, but none of home's homelab wiring; beside the admin's configs/secrets/keys/trusted-gateways, where toggle-trust-network adds the current one while unlocked |
| `base/networkmanager.homelab_dns` | `string?` | `"192.168.178.29"` | The homelab's split-horizon resolver, asked for homelab_domain out a home link (homelab machines); default the lab's router |
| `base/networkmanager.homelab_domain` | `string?` | `"lsck0.dev"` | The homelab's DNS zone |
| `base/networkmanager.homelab_subnets` | `list<string>` | `["10.0.0.0/24", "10.100.0.0/24", "10.200.0.0/24", "10.250.0.0/24"]` | The homelab's subnets, routed straight out a home link and through wg0 elsewhere; default the lab's zones |
| `base/nftables.ssh_knock_window` | `string` | `"1h"` | How long a successful SSH port-knock keeps that IP allowed through to base/ssh.port, nft timeout syntax |
| `base/nftables.ssh_rate` | `string` | `"30/minute burst 30 packets"` | New connections to base/ssh.port one address may open before the rest are dropped, nft limit syntax |
| `base/nftables.pentest_listeners` | `bool` | `false` | Let tun0 (a lab vpn) reach the pentest listener ports (handlers, payload servers) while a trusted link has the inbound ruleset loaded; for machines with the pentesting group |
| `base/oomd.session_memory_low` | `filesize?` | detected | session.slice's MemoryLow, the desktop working set a build's reclaim keeps; null: 15% of RAM, 2 GiB max |
| `base/oomd.pressure_limit_percent` | `int` | `50` | Memory pressure past which systemd-oomd kills the worst app.slice cgroup, held for 20 s |
| `base/pacman.yay_cache_days` | `int` | `30` | Days an unused yay build cache dir may sit in $XDG_CACHE_HOME/yay before yay-cache-clean.timer deletes it, find -mtime argument |
| `base/pam.fido_origin` | `string` | `"pam://lsck0"` | FIDO2 origin and appid every enrolled key's mapping was made for (pamu2fcfg -o) |
| `base/smartd.test_schedule` | `string` | `"S/../.././02\|L/../../6/03"` | When smartd runs self-tests, smartd.conf(5) -s regex syntax (default: short test daily at 02:00, long test Saturday at 03:00) |
| `base/ssh.server` | `bool` | `true` | Run sshd behind the port-knock, and base/endlessh's tarpit on 22; off keeps the client and ssh-agent (wake-pc and offload need it on the target) |
| `base/ssh.port` | `int` | `2222` | The port sshd listens on, reached through the port-knock (sshk, wake-pc, nftables) |
| `base/ssh.knock` | `list<int>` | `[9003, 7001, 8002]` | The three ports knocked in order to open the sshd port to that address (sshk, wake-pc, nftables) |
| `base/ssh.homelab_hosts` | `list<string>` | `["10.0.0.*", "10.100.0.*", "10.200.0.*", "10.250.0.*", "192.168.178.29", "192.168.178.200"]` | ssh patterns of the homelab's guests, router and hypervisor: root, accept-new host keys from known_hosts.homelab (homelab profiles only); default the lab's zones, router and hypervisor |
| `base/ssh.wake_router` | `string?` | `"192.168.178.29"` | The always-on homelab router whose `wol-pc` wakes the desktop (wake-pc, homelab profiles only) |
| `base/ssh.wake_router_tunnel` | `string?` | unset | The router's address inside the wireguard tunnel, which wake-pc asks away from home: its lan address is unrouted there, or shadowed by a foreign lan on the same subnet |
| `base/ssh.wake_host` | `string?` | unset | The desktop wake-pc wakes and then ssh-es into |
| `base/systemd.mem_sleep` | `string?` | unset | Suspend mode written to /sys/power/mem_sleep; unset, the firmware's default |
| `base/systemd.power_key` | `string` | `"suspend"` | What a short press of the power key does, logind.conf(5) HandlePowerKey |
| `base/systemd.power_key_long_press` | `string` | `"poweroff"` | What a long press of the power key does, logind.conf(5) HandlePowerKeyLongPress |
| `base/systemd.lid_switch` | `string` | `"suspend"` | What closing the lid does, logind.conf(5) HandleLidSwitch; lock or ignore keeps a clamshell machine running |
| `base/systemd.lid_switch_external_power` | `string?` | unset | What closing the lid does on external power, HandleLidSwitchExternalPower; unset, as on battery |
| `base/systemd.ntp_servers` | `list<string>` | `[]` | Time servers timesyncd asks, timesyncd.conf(5) NTP; empty, Arch's pool (a network that blocks it needs its own) |
| `base/systemd.bluetooth_auto_enable` | `bool` | `false` | Power bluetooth adapters on at boot and when plugged in |
| `base/tlp.charge_start` | `int` | `95` | Battery charge level below which charging starts (laptops whose firmware supports thresholds) |
| `base/tlp.charge_stop` | `int` | `100` | Battery charge level at which charging stops; 80 spares an always-plugged battery |
| `base/tlp.battery_max_perf_percent` | `int` | `90` | CPU performance cap on battery, percent of the maximum (laptops) |
| `base/tlp.platform_profile_ac` | `string` | `"balanced"` | Firmware platform profile on AC (laptops that have one) |
| `base/tlp.platform_profile_battery` | `string` | `"low-power"` | Firmware platform profile on battery (laptops that have one) |
| `base/tlp.energy_perf_policy` | `string` | `"performance"` | CPU energy/performance policy of a machine without a battery |
| `base/tlp.usb_autosuspend` | `bool` | `true` | Let TLP suspend idle USB devices; off for NICs, DACs, hubs or dongles that drop out and do not resume |
| `base/v4l2loopback.video_nr` | `int?` | detected | /dev/video<n> of the OBS virtual camera; null: a loaded one's, else the first free from 10, past webcams |
| `base/xdg.browser` | `list<string>` | `["firefox.desktop"]` | Desktop entries for web pages and links, first wins |
| `base/xdg.editor` | `list<string>` | `["neovide.desktop", "nvim.desktop", "org.gnome.TextEditor.desktop"]` | Desktop entries for text, source and config files, first wins |
| `base/xdg.file_manager` | `list<string>` | `["org.kde.dolphin.desktop", "nemo.desktop"]` | Desktop entries for folders, first wins |
| `base/xdg.pdf_viewer` | `list<string>` | `["org.kde.okular.desktop", "org.pwmt.zathura.desktop"]` | Desktop entries for PDFs, first wins |
| `base/xdg.image_viewer` | `list<string>` | `["feh.desktop", "nsxiv.desktop"]` | Desktop entries for images, first wins (raw photos stay with rawtherapee) |
| `base/xdg.media_player` | `list<string>` | `["mpv.desktop"]` | Desktop entries for audio and video, first wins |
| `base/xdg.autostart_hidden` | `list<string>` | `[print-applet, geoclue-demo-agent, remmina-applet]` | XDG autostart entries hidden from the session, by desktop file id |
| `base/zram.size` | `string` | `"ram"` | Size of the zram swap device, zram-generator.conf(5) zram-size expression over ram (MiB) |
| `base/zram.compression_algorithm` | `string` | `"zstd"` | Compression used for the zram swap device, zram-generator.conf(5) compression-algorithm (a weaker CPU may prefer lz4) |
| `base/zram.swappiness` | `int` | `150` | How aggressively the kernel swaps to zram versus reclaiming page cache, sysctl(8) vm.swappiness (a zram swap favors higher than disk swap's usual 60) |
| `core/btop.accent` | `string` | `"c4"` | Palette slot for titles, highlights and the selection |
| `core/btop.update_ms` | `int` | `500` | Milliseconds between samples |
| `core/btop.temp_scale` | `string` | `"celsius"` | Unit of the temperature readouts |
| `core/fastfetch.on_shell_start` | `bool` | `true` | Run fastfetch (system summary, local address) atop each new top-level terminal, zsh and nushell |
| `core/git.default_branch` | `string` | `"master"` | Branch git init starts with, init.defaultBranch |
| `core/git.pull_rebase` | `bool` | `true` | git pull rebases local commits instead of merging, pull.rebase |
| `core/git.side_by_side` | `bool` | `true` | delta shows diffs in two columns, delta.side-by-side |
| `core/git.user_name` | `string?` | unset | Commit author name of a login that is not the owner, user.name; unset takes its profile's name |
| `core/git.user_email` | `string?` | unset | Commit author email of a login that is not the owner, user.email; unset takes its profile's email |
| `core/gnupg.cache_ttl` | `int` | `28800` | Seconds gpg-agent caches a passphrase after use before re-asking, gpg-agent.conf(5) default-cache-ttl; a screen lock or suspend empties the cache |
| `core/gnupg.cache_ttl_max` | `int` | `86400` | Seconds gpg-agent caches a passphrase at most, however often it is used, gpg-agent.conf(5) max-cache-ttl |
| `core/herdr.prefix` | `string` | `"ctrl+q"` | herdr prefix key, in herdr key syntax |
| `core/herdr.sidebar_width` | `int` | `20` | Sidebar width in columns |
| `core/locale.lang` | `string?` | detected | LANG in /etc/locale.conf; detected: the one bootstrap set |
| `core/locale.formats` | `string?` | detected | Locale for dates, numbers, money, units, paper and addresses (every LC_ except CTYPE, MESSAGES, COLLATE and IDENTIFICATION); unset follows the language |
| `core/locale.keyboard_layout` | `string?` | detected | xkb layout of the console, X11 and the compositor; detected: the one bootstrap set |
| `core/locale.keyboard_variant` | `string?` | detected | xkb variant, e.g. nodeadkeys |
| `core/locale.keyboard_options` | `list<string>?` | detected | xkb options, e.g. ctrl:nocaps |
| `core/locale.wifi_country` | `string?` | detected | Wi-Fi regulatory domain (ISO 3166 alpha-2); detected: the country of the timezone, else the world domain |
| `core/nas.share` | `string` | `"//10.100.0.100/homelab"` | The homelab NAS's smb share mounted at /mnt/homelab (//host/share) |
| `core/nushell.edit_mode` | `string` | `"emacs"` | Line editor keymap |
| `core/nushell.history_size` | `int` | `100000` | Commands the history keeps |
| `core/starship.scan_timeout_ms` | `int` | `500` | Milliseconds starship waits for a directory scan (project file detection) before giving up, starship.toml scan_timeout |
| `core/syncthing.nas_address` | `string?` | `"tcp://10.100.0.100:22000"` | Address of the homelab NAS device (the lab's nas role); discovery is off, so this is how it is found |
| `core/syncthing.versions_max_age_days` | `int` | `30` | Days staggered versioning keeps old versions of files in ~/sync |
| `core/timezone-auto.any_network` | `bool` | `false` | Look the timezone up on any network, not only a trusted one (base/networkmanager's home or trusted gateways), naming this machine's address to ipinfo.io there; a VPN or tor route still skips it |
| `core/tmux.prefix` | `string` | `"C-q"` | tmux prefix key, in tmux key syntax |
| `core/tmux.mouse` | `bool` | `true` | Mouse selects panes and windows, resizes and scrolls |
| `core/trash.retention_days` | `int` | `1` | Days trash-empty.timer keeps a deleted file before purging it, trash-empty(1)'s days argument |
| `core/wallust.palette` | `string` | `"salience"` | wallust palette that picks the colours from a wallpaper |
| `core/yazi.show_hidden` | `bool` | `false` | Show dotfiles |
| `core/yazi.sort_by` | `string` | `"alphabetical"` | File order in a directory |
| `core/yt-dlp.download_dir` | `string` | `"~/downloads/yt-dlp"` | Directory downloads and the download archive go to |
| `core/yt-dlp.container` | `string` | `"mp4"` | Container merged video and audio streams go into, --merge-output-format |
| `core/yt-dlp.sub_langs` | `list<string>` | `["en.*", "de.*"]` | Subtitle languages embedded, as regexes, --sub-langs |
| `core/yt-dlp.vpn_only` | `bool` | `true` | Run yt-dlp only inside base/protonvpn-netns' namespace, never the bare route; without that namespace, or off, yt-dlp and mpv's url playback run direct |
| `core/zsh.history_size` | `int` | `5000` | Commands the history keeps, HISTSIZE and SAVEHIST |
| `creating/audacity.mcp` | `bool` | `true` | Register audacity-mcp with the coding agents; off, no agent session starts its server |
| `creating/blender.mcp` | `bool` | `true` | Register blender-mcp with the coding agents; off, no agent session starts its server |
| `creating/inkscape.mcp` | `bool` | `true` | Register inkscape-mcp with the coding agents; off, no agent session starts its server |
| `creating/obs.vaapi_render_node` | `string?` | detected | The /dev/dri render node the vaapi encoders use, by-path so it survives reboots |
| `creating/obs.canvas` | `string?` | detected | Canvas WxH: every profile's base and video output, and the Bare and VirtualCam collections |
| `creating/obs.mic` | `string?` | detected | The pipewire source node the Mic/Aux of the Streaming and Bare collections captures |
| `creating/obs.webcam` | `string?` | detected | The v4l2 device the VirtualCam collection's Camera captures, by-id so it survives replugging |
| `creating/obs.monitor_device` | `string?` | detected | The pipewire sink node obs monitors audio on |
| `creating/obs.record_encoder` | `string?` | detected | The recording encoder of the Recording and Streaming profiles |
| `creating/obs.stream_encoder` | `string?` | detected | The streaming encoder; h264 is what every ingest takes |
| `creating/obs.virtualcam_height` | `int` | `720` | Height cap of the virtual camera's output, scaled from the canvas |
| `creating/obs.stream_height` | `int` | `1080` | Height cap of the stream's output, scaled from the canvas |
| `creating/obs.mcp` | `bool` | `true` | Register obs-mcp with the coding agents; off, no agent session starts its server |
| `creating/openscad.mcp` | `bool` | `true` | Register openscad-mcp with the coding agents; off, no agent session starts its server |
| `desktop/chromium.search_url` | `string?` | unset | Default search engine, {searchTerms} is the query; unset, the homelab's searxng on a homelab machine, else duckduckgo |
| `desktop/color-grading.preset` | `string` | `"default"` | Preset before the toggle first picks one (default: warmer, more contrast; off: the output untouched) |
| `desktop/cursor.active` | `bool` | `true` | Hyprland, X11, gtk and KDE apps take the palette's cursor; off, they keep the stock rose-pine one |
| `desktop/cursor.size_px` | `int` | `30` | Pointer size in Hyprland, X11, gtk and KDE apps; scaled outputs ask for up to twice it |
| `desktop/firefox.search_url` | `string?` | unset | Default search engine, {searchTerms} is the query; unset, the homelab's searxng on a homelab machine, else duckduckgo |
| `desktop/firefox.extensions_off` | `list<string>` | `[]` | Force-installed extensions to leave out by id (seventv-next@7tv.app); the rest stay installed and unremovable |
| `desktop/firefox.save_logins` | `bool` | `false` | Firefox offers to save passwords; off for a separate password manager |
| `desktop/firefox.safe_browsing` | `bool` | `false` | Google Safe Browsing warnings for phishing, malware and downloads |
| `desktop/ghostty.cursor_style` | `string` | `"block"` | Text cursor shape |
| `desktop/ghostty.cursor_blink` | `bool` | `true` | Text cursor blinks |
| `desktop/ghostty.window_columns` | `int` | `115` | A new window's width in cells |
| `desktop/ghostty.window_rows` | `int` | `35` | A new window's height in cells |
| `desktop/ghostty.scroll_multiplier` | `float` | `1.5` | Mouse and touchpad scroll distance multiplier |
| `desktop/gtk.button_layout` | `string` | `":"` | Client-side title bar buttons, gnome's button-layout form (left:right, e.g. close,minimize:) |
| `desktop/hyprland.monitors` | `list<record>?` | detected | One hl.monitor per output: output, mode, position, scale; detected from the connected outputs, any other output gets its preferred mode and an auto scale |
| `desktop/hyprland.main_monitor` | `string?` | detected | The output holding workspace 1, the bar's notifications, steam's toasts and the tablet; detected: the internal panel, else the largest, leftmost on a tie |
| `desktop/hyprland.bind_workspaces` | `bool` | `true` | Each workspace lives on its own monitor (the layout below); off, a workspace opens on the focused monitor |
| `desktop/hyprland.workspaces` | `record?` | unset | Workspace to output; unset: the first ceil(10 / outputs) on the main monitor, the rest split over the others left to right |
| `desktop/hyprland.xwayland_scale` | `int?` | unset | GDK_SCALE for X11 apps (force_zero_scaling); unset: the main monitor's scale rounded, else 1 on a laptop and 2 elsewhere |
| `desktop/hyprland.app_workspaces` | `list<record>` | `[]` | Homes for apps by window class: {class, workspace, silent}; silent opens them without switching to their workspace or focusing them |
| `desktop/hyprland.lock_screen` | `string` | `"quickshell"` | The lock screen hypridle and every lock key start; the other is the fallback |
| `desktop/hyprland.monitor_speaker_volume` | `int?` | unset | Every DDC monitor's built-in speaker volume (VCP 0x62), set at session start; 0 silences speakers fed by DisplayPort audio, which can pop on wake |
| `desktop/hyprland.autostart` | `list<record>` | `[]` | Apps started once per login: {cmd, workspace?, float?, after?}; workspace and float apply to the window the command's own process opens; after names a window class whose first window starts this one (an order on a shared workspace) |
| `desktop/hyprland.pointer_sensitivity` | `float` | `0.0` | libinput pointer acceleration, -1 to 1 |
| `desktop/hyprland.natural_scroll` | `bool` | `false` | Touchpad content follows the fingers |
| `desktop/hyprland.left_handed` | `bool` | `false` | Swaps the primary and secondary mouse buttons |
| `desktop/hyprland.accel_profile` | `string` | `"default"` | Pointer acceleration; flat turns it off, default is libinput's per device |
| `desktop/hyprland.focus_follows_mouse` | `bool` | `true` | Focus moves to the window under the pointer; off, a click focuses |
| `desktop/hyprland.cursor_shake` | `bool` | `true` | Shaking the pointer enlarges it (the dynamic-cursors plugin); off, the plugin is neither built nor loaded |
| `desktop/hyprland.repeat_rate_hz` | `int` | `30` | Key repeats per second while held |
| `desktop/hyprland.repeat_delay_ms` | `int` | `400` | Hold time before a key repeats |
| `desktop/hyprland.numlock` | `bool` | `true` | Num lock on at login |
| `desktop/hyprland.tap_to_click` | `bool` | `true` | A touchpad tap clicks |
| `desktop/hyprland.touchpad_scroll_factor` | `float` | `0.5` | Touchpad scroll distance multiplier |
| `desktop/hyprland.cursor_hide_s` | `int` | `10` | Idle seconds until the cursor hides, 0 never |
| `desktop/hyprland.gaps_in_px` | `int` | `4` | Gap between tiled windows |
| `desktop/hyprland.border_px` | `int` | `1` | Window border width, the focused window's in the accent gradient |
| `desktop/hyprland.gaps_out_px` | `int` | `8` | Gap between tiled windows and the screen edge |
| `desktop/hyprland.blur` | `bool` | `true` | Blur behind translucent windows and popups |
| `desktop/hyprland.blur_menus` | `bool` | `true` | Blur behind popups and untitled floating X11 windows (menus, tooltips) |
| `desktop/hyprland.shadows` | `bool` | `true` | Drop shadows under windows |
| `desktop/hyprland.animations` | `bool` | `true` | Window, layer and workspace animations; power saver turns them off regardless |
| `desktop/hyprland.vrr` | `string` | `"off"` | Adaptive sync; fullscreen_games: fullscreen video and game windows only |
| `desktop/hyprland.idle_dim_s` | `int` | `900` | Idle seconds until the screens dim |
| `desktop/hyprland.idle_lock_s` | `int` | `1200` | Idle seconds until the session locks |
| `desktop/hyprland.idle_dpms_s` | `int` | `2100` | Idle seconds until the screens go off |
| `desktop/hyprland.idle_suspend` | `bool` | `true` | Suspend after the idle times below; off, idle never suspends |
| `desktop/hyprland.idle_dim_monitors` | `bool` | `true` | Idle dim also lowers external monitors over DDC/CI; off, only the panel backlight and keyboard light dim |
| `desktop/hyprland.idle_suspend_s` | `int` | `2400` | Idle seconds until suspend, unless an agent works or an inhibitor holds |
| `desktop/hyprland.idle_dim_saver_s` | `int` | `300` | Idle seconds until the screens dim in power saver (a laptop on battery) |
| `desktop/hyprland.idle_lock_saver_s` | `int` | `600` | Idle seconds until the session locks in power saver |
| `desktop/hyprland.idle_dpms_saver_s` | `int` | `660` | Idle seconds until the screens go off in power saver |
| `desktop/hyprland.idle_suspend_saver_s` | `int` | `1800` | Idle seconds until suspend in power saver |
| `desktop/hyprland.screen_shader` | `string?` | unset | Shader each login starts with, a toggle-shader.nu list name (colorblind-correction:deuteranopia) |
| `desktop/idle-guards.guards` | `list<string>` | `[media, mic, ssh]` | What holds off sleep: media (a player plays), mic (a microphone records), ssh (an ssh session is open) |
| `desktop/kdeconnect.plugins_off` | `list<string>` | `[kdeconnect_notifications, kdeconnect_sendnotifications, kdeconnect_sms, kdeconnect_contacts, kdeconnect_mousepad, kdeconnect_remotekeyboard, kdeconnect_runcommand, kdeconnect_lockdevice, kdeconnect_shareinputdevices, kdeconnect_shareinputdevicesremote, kdeconnect_digitizer, kdeconnect_presenter]` | KDE Connect plugins turned off for every paired device on each apply; drop one to use it (phone notifications, SMS, the phone as remote or presenter) |
| `desktop/kdeconnect.clipboard_auto` | `bool` | `false` | Send every desktop copy to the paired phone, passwords from a password manager excluded |
| `desktop/ly.clock` | `string?` | `"%H:%M:%S"` | The greeter's clock, a strftime format; unset, no clock |
| `desktop/ly.session` | `string` | `"Hyprland"` | Session preselected for a user ly has not seen yet; ly remembers each user's last one |
| `desktop/mpv.ytdl_max_height` | `int` | `2160` | Max video height yt-dlp fetches for a stream (ytdl-format height filter, pixels); applies to mpv-stream, plain mpv runs no yt-dlp |
| `desktop/mpv.hwdec` | `string` | `"auto-safe"` | Hardware video decoding (mpv hwdec) |
| `desktop/pipewire.app_loopbacks` | `bool` | `true` | Every app plays through a loopback of its own that carries its system volume, so a capture of the app (obs) stays at full level |
| `desktop/pipewire.eq_target` | `string?` | unset | The node.name of the headset sink the eq attaches to as a smart filter; unset, no eq chain |
| `desktop/pipewire.disabled_cards` | `list<string>` | `[]` | Sound cards wireplumber leaves off, by device.name (wpctl status, pactl list cards): their outputs never show up nor catch the fallback when the headset goes |
| `desktop/pipewire.eq_preset` | `string` | `"pro-x-2.txt"` | AutoEq ParametricEQ preset for that headset, a file in this module or an absolute path |
| `desktop/plasma.kwin_outputs` | `bool?` | detected | Ship the committed kwin output layout; detected: on when a connected monitor's EDID is one it describes |
| `desktop/plasma.locale` | `bool` | `true` | Ship plasma-localerc with core/locale's language |
| `desktop/printing.page_size` | `string` | `"A4"` | Default paper of every queue (PPD PageSize) |
| `desktop/qbittorrent.interface` | `string?` | unset | Interface qBittorrent is bound to; empty, none; unset, base/protonvpn's proton0 where the profile has secrets |
| `desktop/quickshell.pomodoro_focus_min` | `int` | `25` | Minutes of one focus block |
| `desktop/quickshell.pomodoro_break_min` | `int` | `5` | Minutes of the short break after a focus block |
| `desktop/quickshell.pomodoro_long_break_min` | `int` | `15` | Minutes of the long break after the last focus block of a round |
| `desktop/quickshell.pomodoro_cycles` | `int` | `4` | Focus blocks before a long break |
| `desktop/quickshell.clipboard_history_max_age_h` | `int` | `12` | Hours a copied text or image stays in the clipboard history |
| `desktop/quickshell.bar_left` | `list<string>` | `[AppMenu, Workspaces, Submap]` | Widgets on the left of the main bar, by plugins/bar/widgets name |
| `desktop/quickshell.bar_center` | `list<string>` | `[Clock, Weather, Media, Obs, Discord]` | Widgets in the middle of the main bar |
| `desktop/quickshell.bar_right` | `list<string>` | `[Tray, Separator, Agents, Phone, Homelab, System, Drives, Network, Display, AudioIO, Notifications, KeyboardLayout, Indicators, Exit]` | Widgets on the right of the main bar |
| `desktop/quickshell.bar_secondary_left` | `list<string>` | `[AppMenu, Workspaces, Submap]` | Widgets on the left of every other screen's bar |
| `desktop/quickshell.bar_secondary_center` | `list<string>` | `[]` | Widgets in the middle of every other screen's bar |
| `desktop/quickshell.bar_secondary_right` | `list<string>` | `[]` | Widgets on the right of every other screen's bar |
| `desktop/quickshell.notification_low_s` | `int` | `5` | Seconds a low urgency popup stays at least |
| `desktop/quickshell.notification_normal_s` | `int` | `8` | Seconds a normal popup stays at least; critical ones stay until dismissed |
| `desktop/quickshell.notification_max_s` | `int` | `30` | Seconds a popup stays at most, whatever its sender asks |
| `desktop/quickshell.notification_history_max` | `int` | `30` | Notifications kept in the history |
| `desktop/quickshell.fx_glow` | `float` | `0.22` | Accent glow around text and edges |
| `desktop/quickshell.fx_scanlines` | `float` | `0.06` | Opacity of the scanline overlay |
| `desktop/quickshell.fx_flicker` | `float` | `0.02` | CRT brightness flicker |
| `desktop/quickshell.fx_matrix_rain` | `float` | `0.5` | Glyph rain on the lock screen |
| `desktop/quickshell.fx_corner_brackets` | `bool` | `true` | Corner brackets on panels and cards |
| `desktop/quickshell.fx_motion` | `bool` | `true` | Shell animations: glitch, shake, reveals, typing; off as under the power saver |
| `desktop/quickshell.fx_glitch` | `bool` | `true` | Glitch flash on lock, unlock and launch |
| `desktop/quickshell.desktop_quote` | `bool` | `true` | Daily quote on the wallpaper |
| `desktop/quickshell.desktop_quotes_file` | `string?` | unset | JSON list of {text, author} to draw the daily quote from instead of the built-in one |
| `desktop/quickshell.desktop_agenda` | `bool` | `true` | Tasks, reminders, events and the pomodoro on the wallpaper |
| `desktop/quickshell.lock_show_media` | `bool` | `true` | Playing track on the lock screen |
| `desktop/quickshell.lock_show_notifications` | `bool` | `true` | Unread notifications on the lock screen |
| `desktop/quickshell.sounds` | `bool` | `true` | Chimes for alerts, reminders and pomodoro phases |
| `desktop/quickshell.notification_position` | `string` | `"right"` | Corner of the screen popups stack in, below the bar |
| `desktop/quickshell.weather_units` | `string` | `"metric"` | Units of the weather widget |
| `desktop/quickshell.weather_location_sources` | `list<string>` | `[geoclue, timezone, ipgeo]` | Where weather looks for the location, in order, when none is pinned; geoclue and ipgeo ask online services |
| `desktop/quickshell.clock_zones` | `list<string>` | `["NA West=America/Los_Angeles", "NA Central=America/Chicago", "NA East=America/New_York", "UK=Europe/London", "Central EU=Europe/Berlin", "NZ=Pacific/Auckland", "JP=Asia/Tokyo"]` | World clocks in the clock panel: an IANA zone, or label=zone |
| `desktop/quickshell.bar_spectrum` | `bool` | `true` | Audio spectrum behind the bar's media widget |
| `desktop/quickshell.agent_usage_limits` | `bool` | `true` | Rate-limit bars in the agents widget; each refresh sends a one-token request on your Claude plan |
| `desktop/qutebrowser.search_url` | `string?` | detected | The default search engine, {} is the query; unset, the homelab's searxng on a homelab machine, else duckduckgo |
| `desktop/qutebrowser.search_method` | `string` | `"GET"` | The startpage's search form method; most engines, the homelab's searxng too, take GET; POST works only in qutebrowser |
| `desktop/qutebrowser.tabs_position` | `string` | `"top"` | Where the tab bar sits |
| `desktop/qutebrowser.tabs_show` | `string` | `"multiple"` | When the tab bar shows: always, never, with more than one tab, or while switching |
| `desktop/qutebrowser.statusbar_show` | `string` | `"in-mode"` | When the status bar shows; in-mode, only outside normal mode |
| `desktop/qutebrowser.startpage_links` | `list<record>` | `[]` | Start page links, also firefox's home: {group, sub?, name, url}; for a profile without secrets, whose weblinks module writes them |
| `desktop/qutebrowser.lists_max_age_days` | `int` | `7` | Age at which the adblock lists are fetched again on the next apply |
| `gaming/d2launcher.base_dir` | `string?` | detected | A Diablo II: Lord of Destruction install the game dir is seeded from; detected in the lutris prefixes |
| `gaming/d2launcher.resolution` | `string?` | detected | The monitor the render size derives from, WxH; detected from the focused monitor |
| `gaming/d2launcher.render_size` | `string?` | unset | The 4:3 size the game renders at inside gamescope, WxH; the monitor's full height by default |
| `gaming/d2launcher.upscale_filter` | `string` | `"linear"` | gamescope's upscale filter for every Diablo II launcher, -F |
| `gaming/ffxiv.mangohud` | `bool` | `true` | Start XIVLauncher with MANGOHUD=1, the overlay over the game |
| `gaming/gamemode.gpu_device` | `int?` | detected | The /dev/dri/cardN gamemode tunes while a game runs; none leaves the gpu alone |
| `gaming/gamemode.amd_performance_level` | `string?` | detected | The amdgpu power_dpm_force_performance_level during a game; high holds the clocks up, wasteful on battery |
| `gaming/gamemode.renice` | `int` | `10` | Niceness gamemode lowers a game by, gamemode.ini renice |
| `gaming/gamemode.pin_cores` | `bool` | `true` | Pin a game to the cores with the largest l3 (an x3d's v-cache ccd) |
| `gaming/lutris.dpi` | `int?` | detected | Logical dpi wine apps draw at under xwayland (LogPixels), 96 times the main monitor's scale |
| `gaming/mangohud.font_size` | `int` | `18` | MangoHud overlay text size in pixels, MangoHud.conf font_size |
| `gaming/mangohud.position` | `string` | `"top-left"` | MangoHud overlay corner, MangoHud.conf position |
| `gaming/pd2.game_dir` | `string?` | detected | The season 3 ProjectD2 dir; detected under ~/sync/games/d2 |
| `gaming/pd2.save_dir` | `string?` | detected | Season 3's single player saves (.d2s, plugy's .d2x and .sss); detected as Save beside the install |
| `gaming/pd2.s14_save_dir` | `string?` | detected | Season 14's single player saves and shared stash; detected as ~/sync/games/d2/Save-S14 when it exists |
| `gaming/steam.launch_options` | `string` | `"gamemoderun mangohud %command%"` | Launch options filled into every installed game whose own are empty or ours; empty for none, %command% is the game |
| `gaming/steam.millennium` | `bool` | `true` | The Millennium client mod with the themed cyberpunk skin; off unlinks it for this login, the package stays |
| `gaming/vkbasalt.sharpness` | `float` | `0.4` | Contrast adaptive sharpening strength, vkBasalt.conf casSharpness |
| `gaming/vkbasalt.enable_on_launch` | `bool` | `true` | Effects on from a game's start; Home toggles them |
| `latex/sioyek.new_window` | `bool` | `true` | Open each file in its own window |
| `latex/sioyek.page_separator_px` | `int` | `8` | Gap between pages |
| `latex/zotero.mcp` | `bool` | `true` | Register zotero-mcp with the coding agents; off, no agent session starts its server |
| `llm/comfyui.idle_min` | `int` | `10` | Idle minutes after the last editor tab or request before ComfyUI stops |
| `llm/ollama.vram_percent` | `int` | `80` | Share of the largest gpu's vram ollama may fill; the rest stays free for the desktop, and a model that does not fit runs partly on the cpu |
| `llm/ollama.parallel` | `int` | `4` | Requests one loaded model answers at once; each slot holds its own context in vram |
| `llm/ollama.keep_alive_min` | `int` | `30` | Idle minutes before a loaded model is unloaded and ollama stops |
| `llm/ollama.pull_models` | `bool` | `true` | Pull the pinned models (tens of GB) where a gpu has the vram for them; off leaves the store to ollama pull |
| `llm/ollama.prune_unpinned` | `bool` | `true` | Remove every model the pins do not keep after a pull, those pulled by hand included |
| `llm/vllm.model` | `string` | `"RogerS-01/Josiefied-Qwen3-8B-abliterated-v1-AWQ"` | The hugging face repo vllm serves; an uncensored 4-bit AWQ build of Josiefied-Qwen3-8B-abliterated-v1 |
| `llm/vllm.model_revision` | `string` | `"0244c2514cc272a603368c0440ff3002143b2336"` | The model repo's commit, weights and tokenizer alike; bump from https://huggingface.co/api/models/<model>/revision/main |
| `llm/vllm.tool_call_parser` | `string` | `"hermes"` | vllm's tool call parser for the model's chat format (hermes for qwen3, gemma4 for gemma 4) |
| `llm/vllm.reasoning_parser` | `string` | `"qwen3"` | vllm's reasoning parser, which moves the model's thinking out of the reply into reasoning_content |
| `llm/vllm.gpu_memory_utilization` | `float?` | detected | The share of vram vllm takes; the rest stays for the desktop rendering on the same card |
| `llm/vllm.kv_cache_dtype` | `string` | `"fp8"` | fp8 halves the kv cache's vram use but has no native matrix support on RDNA3; auto (bf16) is faster there |
| `llm/vllm.context` | `int` | `65536` | The context window vllm serves; Hermes needs 64000. Past the model's native 32768 it switches on YaRN rope scaling |
| `llm/vllm.idle_min` | `int` | `5` | Idle minutes after the last request before vllm stops and frees its vram |
| `pentesting/metasploit.idle_min` | `int` | `15` | Idle minutes after the last rpc client before msfrpcd and its postgres stop |
| `pentesting/wireshark.mcp` | `bool` | `true` | Register wireshark-mcp with the coding agents; off, no agent session starts its server |
| `programming/act.container_memory` | `string` | `"12g"` | Memory cap of each job container (podman --memory) |
| `programming/act.container_cpus` | `int` | `4` | CPUs of each job container |
| `programming/act.prune_age_days` | `int` | `30` | Age past which an unused tagged image is pruned |
| `programming/android.avd` | `string` | `"nya35"` | Name of the emulator image made from the system image; empty makes none |
| `programming/android.avd_device` | `string` | `"pixel_6"` | Hardware profile of a new emulator image (avdmanager list device) |
| `programming/cargo.sccache_redis` | `bool` | `false` | Compile through sccache with the homelab's shared redis cache (secret sccache.env); plain rustc whenever it is unreachable |
| `programming/caveman.default_mode` | `string` | `"caveman"` | Voice every agent session starts in: off for normal replies, manual for only after /caveman |
| `programming/claude.model` | `string` | `"claude-opus-5-5"` | The model every session starts on |
| `programming/claude.effort` | `string` | `"medium"` | Reasoning effort of that model |
| `programming/claude.voice` | `bool` | `true` | Voice dictation, hold to talk |
| `programming/claude.remote_control` | `bool` | `false` | Every session registers with the remote-control relay at start. It needs Claude's feature flags, so on, DO_NOT_TRACK is lifted for claude and usage telemetry is sent; off, telemetry is off |
| `programming/copilot.model` | `string` | `"claude-sonnet-5"` | The model every session starts on |
| `programming/debugging.raddbg_font_px` | `float` | `10.5` | raddbg's font size before the X11 scale; set once per value, a size picked in the app stays |
| `programming/docker.prune_age_days` | `int` | `7` | Age past which dangling images and build cache are pruned |
| `programming/hermes.system_agent` | `bool` | `false` | An always-on Hermes session (profile system, unit hermes-system-agent) that drives the desktop and talks: SUPER+grave shows it, SUPER+ALT+a talks to it |
| `programming/hermes.model` | `string` | `"claude-sonnet-5"` | The model every session starts on |
| `programming/hermes.delegation_model` | `string` | `"claude-sonnet-5"` | The model subagents run on |
| `programming/hermes.system_voice` | `string` | `"en_US-lessac-medium"` | Piper voice the system agent answers in |
| `programming/hermes.system_stt_model` | `string` | `"small"` | Local whisper model the system agent hears with |
| `programming/jetbrains.autostart` | `bool` | `false` | Toolbox starts with the session |
| `programming/nvim.spell_languages` | `list<string>` | `[en]` | Spell-check languages of prose buffers (markdown, tex, commits), e.g. en, de; nvim offers to download a missing one |
| `programming/nvim.dictation_language` | `string` | `"en"` | Language <M-v> dictation transcribes, a whisper code such as en or de, or auto to detect it |
| `programming/offload.memory_cap_mib` | `int?` | unset | MiB the offload jobs of one user may use together (offload.slice), a job's memoryMiB at most this; none: half the RAM |
| `programming/offload.cpus_cap` | `int?` | unset | CPUs the offload jobs of one user may use together, a job's cpus at most this; none: half the cores |
| `programming/playwright.headless` | `bool` | `true` | The agents' browsers run without a window |
| `programming/task.sync_url` | `string?` | unset | The taskchampion server every replica syncs with as the one client of configs/secrets/keys/taskwarrior-*; none: no sync |
| `programming/task.recurrence` | `bool` | `true` | This replica creates the instances of recurring tasks; one per sync, or each adds its own copy (task-sync(5)) |
| `programming/task.sync_interval_min` | `int` | `30` | Minutes between the timer's syncs; a divisor of 60, so the steps within each hour are even |
| `programming/task.week_start` | `string` | `"Monday"` | First day of the week |
| `programming/task.date_format` | `string` | `"d.m.y"` | Taskwarrior date format of input, reports and annotations |
| `programming/trmnl-claude.poster` | `bool` | `false` | This machine posts its Claude usage to the TRMNL panel; one poster per panel, a second would overwrite it |
| `programming/trmnl-claude.interval_min` | `int` | `15` | Minutes between posts; a divisor of 60, so the steps within each hour are even |
| `programming/zed.vim_mode` | `bool` | `true` | Vim keys in the editor |
| `programming/zed.format_on_save` | `bool` | `true` | Format a buffer on save |
| `qemu/libvirt.nested` | `bool` | `true` | KVM guests may run their own guests |
| `qemu/waydroid.multi_windows` | `bool` | `true` | Each Android app in its own resizable window |
| `socials/discord.plugins` | `list<string>` | `[LastMessageDate, ZipPreview, DoNotTrack, BetterDoubleClickToEdit, DoubleClickToReply, "LaTeX Generator", PriorityDM, Incognito, "High-Res Profile Images", OpenInApp, SpotifyEnhance, "Hide Chat Icons"]` | Third-party BetterDiscord plugins fetched at their pins and enabled; empty for none (client mods break Discord's terms) |
| `socials/discord.devtools` | `bool` | `true` | Discord's devtools (ctrl+shift+i), to debug a plugin; the console is where self-XSS scams ask to paste code |
| `socials/spotify.adblock` | `bool` | `true` | Inject spicetify's adblock extension |
| `socials/spotify.music_videos_hidden` | `bool` | `true` | Inject the extension that hides music videos |
<!-- options end -->
