# Features

Everything here is set up by the install (bootstrap, then `dot apply`) and kept current by `dot sync`.
`dot plan --modules`, `dot set` and `hyprctl binds` list modules, options and keybinds. SUPER is the mod key.

## dot

- `dot sync`: pull, migrate, install, apply, back up app state, signed `Generation: <n>` commit, push.
- `dot apply`, `dot plan`, `dot status`, `dot set`, `dot theme`, `dot module adopt|reset|unlink|remove|restore`,
  `dot explain`, `dot log`, `dot secrets`, `dot test lint|check|fmt|run`: see `dot --help`.
- Platforms `luca-pc`, `luca-notebook`, `server`, `vm`, `wsl`; profile `luca` (owner, with secrets) or `custom`.
- Install: the lsck0 iso (answer file optional) or `curl | sh` from the official Arch ISO or WSL.
- `[lsck0]` package mirror built by the homelab from `mirror/`.

## Security

- AppArmor (apparmor.d plus own profiles, content openers enforced), KSPP cmdline, sysctl hardening.
- LUKS root: TPM2+PIN, YubiKey FIDO2 or passphrase; remote unlock over initramfs ssh; secure boot with own keys, UKIs.
- sudo and polkit: YubiKey touch or fingerprint (fprintd), password fallback.
- nftables lockdown by default, inbound opens on home networks, port-knocked sshd; with `untrusted_policy` lockdown-tor
  (luca-pc, luca-notebook) an egress kill switch off home.
- fail2ban, an endlessh tarpit on port 22, the OSSEC HIDS with its alerts in the bar's system panel.
- Untrusted networks: random MAC, ProtonVPN or tor; fail-closed VPN namespace for `vpn <cmd>`; Portmaster.
- Secrets in a git-crypt submodule unlocked with the YubiKey; per-repo credential isolation (`identity-init`).
- Telemetry off everywhere; browser policies; sandboxed builds (`sandbox-build`), confined GUI apps (`confine`).

## Desktop

- Hyprland (Lua config), uwsm, ly; Plasma as a second session.
- quickshell: bar with clock, weather, media, OBS, Discord, agents, homelab, system, network, display, audio and
  notification panels; launcher, clipboard (with OpenPGP), settings window, tasks and notes, overview, power menu, lock,
  OSD, reminders, pomodoro, desktop agenda.
- Toggles (`scripts/toggles/`; `prefix+m` in tmux and herdr, the bar, the settings window on `SUPER+comma`): route
  (direct, proton, tor, offline), homelab VPN, firewall, captive portal, radios, focus, night light, shaders, color
  grading, power mode, font, theme mode and more.
- Theming: 34 palettes or wallust from the wallpaper, applied live to every themed app (`dot theme`, `SUPER+w`).
- Idle: dim, lock, screens off, suspend; guards for media, ssh and working agents. Lid closed with an external monitor
  moves the desktop there.
- Power and disks: tlp, zram, the sched_ext lavd scheduler on laptops, smartd, the CPU package's draw in the bar.
- Shimeji desktop mascots.

## Apps

- Shell: zsh and nushell, starship, tmux and herdr, ghostty, yazi, about 60 CLI tools.
- Editors: Neovim (LSPs for about 40 languages via mason), Emacs, VSCodium, Zed, JetBrains.
- Agents: Claude Code, Copilot, Gemini, Hermes, sharing `skills/`; MCP servers registered per app.
- Toolchains for C, Rust, Go, Zig, Odin, Haskell, OCaml, Lean, Jai, Java, .NET, Node, Android; nix, devenv, docker,
  podman, kubernetes, PostgreSQL; Forgejo (`tea`) and Grafana MCP for the homelab.
- Mail (Thunderbird), LibreOffice, zathura, Obsidian, VeraCrypt.
- Browsers: Firefox, Chromium, qutebrowser. Chat: Signal, Telegram, Element, Discord, TeamSpeak. Spotify (spicetify).
- Taskwarrior with the homelab sync server, timewarrior, bugwarrior; homelab calendar on the desktop agenda.
- LLMs: ollama and vLLM (ROCm), socket activated, abliterated (uncensored) models pinned by digest; ollama splits a
  model too big for the GPU into RAM; Alpaca as a desktop client.
- Gaming: Steam, Proton, gamemode, MangoHud, FFXIV with Dalamud, Lutris, Diablo II (vanilla, Median XL, PD2 S3 and
  S14), Minecraft, VR, emulators (RetroArch, melonDS, mGBA), NetHack.
- Creating: OBS (streaming, recording, virtual cam), Blender, GIMP, Krita, Inkscape, kdenlive, Audacity, OpenSCAD;
  Godot and Unreal with MCP.
- LaTeX, Zotero; libvirt, Waydroid; a pentesting toolkit.

## Backups

- Config in git; app state in the secrets submodule (`keys/` encrypted, `state/` plain), backed up by `dot sync`.
- `~/sync` via syncthing with the NAS; NAS share at `/mnt/homelab`.

## Keybinds

Keys are SUPER plus the named key unless written as a full chord; `hyprctl binds` prints every bind with its
description.

- Apps: terminal (`Return`, kitty on `SHIFT+Return`), Firefox (`a`), qutebrowser (`SHIFT+a`), file manager (`e`),
  editor (`n`), notes pad (`SHIFT+n`), system monitor (`SHIFT+t`), magnifier (`x`), desktop mascots (`y`, `SHIFT+y`
  stops them).
- Shell: launcher (`d`, `ALT+d` runs from `$PATH`), clipboard (`v`), overview (`Tab`, a submap while open), tasks
  (`o`), settings (`comma`), timer (`t`), wallpaper picker (`w`), power menu (`SHIFT+e`), lock (`Escape`), restart
  quickshell (`SHIFT+r`), discord mute (`m`).
- Bar panels: `b` then a letter (audio, notifications, clock, display, homelab, agents, media, network, obs, system,
  discord voice, weather).
- Windows: focus and move (`hjkl` or arrows, `SHIFT`), close (`q`), float (`space`), fullscreen (`f`), previous
  window (`s`), split (`g`), groups (`CTRL+hjkl`, `CTRL+w`, `c`), resize mode (`r`), mouse move and resize.
- Workspaces: `1` to `0` focus, `SHIFT` moves the window there.
- Capture: a region (`Print` alone or `SHIFT+s`), the monitor (`SHIFT+Print` without SUPER), the window (`Print`),
  color picker (`p`), OBS replay buffer (`F9` saves, `SHIFT+F9` starts or stops), MangoHud (`SHIFT+F12` without
  SUPER).
- Media and hardware keys, also on the lock screen: playback, volume, mic mute, brightness (`SHIFT` for software
  brightness), keyboard backlight (`SHIFT+b`), lid switch.

## Modules

Every module under `configs/`, the owner's own in `configs/secrets/` aside. A platform runs the groups it lists.

<!-- modules: generated by dot internal gen from configs/ -->
| group | modules |
|---|---|
| `base` | `apparmor`, `boot/hardening`, `boot/luks`, `boot/remote-unlock`, `boot/sbctl`, `boot/systemd-boot`, `cleanup`, `coredump`, `dot`, `endlessh`, `essentials`, `fail2ban`, `failure-notify`, `fancontrol`, `fprintd`, `fwupd`, `ghostmirror`, `hardening`, `hardware`, `i2c`, `lact`, `networkmanager`, `nftables`, `oomd`, `ossec`, `pacman`, `pam`, `perf`, `plymouth`, `portmaster`, `powercap`, `protonvpn`, `protonvpn-netns`, `resolved`, `sandbox`, `scx`, `smartd`, `ssh`, `sudo`, `systemd`, `tablet`, `tlp`, `tor`, `v4l-utils`, `v4l2loopback`, `wireguard`, `xdg`, `yubikey`, `zram` |
| `core` | `btop`, `cli`, `fastfetch`, `gh`, `git`, `gnupg`, `herdr`, `locale`, `nas`, `ntfy`, `nushell`, `proton/pass`, `proton/sessions`, `starship`, `syncthing`, `timezone-auto`, `tmux`, `toggles`, `trash`, `veracrypt`, `wallust`, `yazi`, `yt-dlp`, `zsh` |
| `creating` | `apps`, `audacity`, `blender`, `gimp`, `inkscape`, `krita`, `obs`, `openscad` |
| `desktop` | `applications`, `bookokrat`, `chromium`, `color-grading`, `feather`, `firefox`, `ghostty`, `gparted`, `gtk`, `hyprland`, `idle-guards`, `jdownloader`, `kitty`, `libreoffice`, `ly`, `mpv`, `nsxiv`, `obsidian`, `oomox`, `pipewire`, `plasma`, `printing`, `qbittorrent`, `quickshell`, `qutebrowser`, `shimoji`, `thunderbird`, `uwsm`, `zathura` |
| `fonts` | `fonts` |
| `gaming` | `d2launcher`, `dalamud`, `emulators`, `ffxiv`, `gamemode`, `games`, `lutris`, `mangohud`, `modrinth`, `nethack`, `pd2`, `protonup`, `runtime`, `steam`, `vkbasalt`, `vpn-bypass`, `vr` |
| `latex` | `latex`, `sioyek`, `zotero` |
| `llm` | `alpaca`, `ollama`, `tools`, `vllm` |
| `pentesting` | `caido`, `ghidra`, `llm-jailbreaks`, `metasploit`, `netscanner`, `nuclei`, `pentest`, `proxychains`, `rustscan`, `seclists`, `toolkit`, `wireshark`, `zaproxy` |
| `programming` | `act`, `agent-rules`, `android`, `asm-lsp`, `bruno`, `bugwarrior`, `cargo`, `caveman`, `cgdb`, `claude`, `copilot`, `debugging`, `devtools`, `direnv`, `docker`, `elan`, `emacs`, `flux`, `forgejo`, `formatting`, `gdb`, `gemini-cli`, `gh-dash`, `ghcup`, `godot`, `grafana`, `hermes`, `http`, `infra`, `jai`, `jetbrains`, `kani`, `kubernetes`, `lazygit`, `math`, `nietzschian`, `nix`, `nnd`, `nvim`, `opam`, `playwright`, `postgres`, `projects`, `python`, `registry`, `renderdoc`, `rtk`, `security`, `task`, `toolchains`, `trmnl-claude`, `typos`, `unreal`, `vcs`, `verification`, `vscode`, `zed` |
| `qemu` | `containers`, `libvirt`, `waydroid` |
| `rocm` | `compute` |
| `socials` | `apps`, `desktop`, `discord`, `element`, `spotify`, `teamspeak`, `telegram` |
<!-- modules end -->

## Options

Every typed option besides `enable`. Detected: set from the hardware when the platform and profile leave it unset.

<!-- options: generated by dot internal gen from each module's options -->
| option | type | default | what it does |
|---|---|---|---|
| `base/boot/hardening.allow_smt` | `bool` | `false` | Keep hyperthreading despite MDS/MMIO, accepting the cross-sibling leak for the threads |
| `base/boot/remote-unlock.ssh_unlock` | `bool` | `false` | Wake-on-lan this machine, then ssh into the initramfs to unlock LUKS remotely |
| `base/boot/remote-unlock.wifi` | `bool` | `false` | Also join the home wifis (configs/secrets/keys/wifi) in the initramfs; their keys are written into the image |
| `base/cleanup.journal_max_use` | `string` | `"500M"` | Total disk space the systemd journal may keep, journald.conf(5) size syntax |
| `base/coredump.max_use` | `string` | `"256M"` | Total disk space systemd-coredump may keep across every stored core, systemd.coredump(5) size syntax |
| `base/coredump.process_size_max` | `string` | `"1G"` | Largest process core systemd-coredump will process at all, above it the core is skipped entirely |
| `base/coredump.external_size_max` | `string` | `"1G"` | Largest core systemd-coredump will write to storage, independent of the process size limit |
| `base/fail2ban.bantime` | `int` | `3600` | Seconds an IP stays banned after too many failed attempts, fail2ban jail.conf(5) bantime |
| `base/fail2ban.findtime` | `int` | `600` | Seconds of history fail2ban scans for failed attempts, fail2ban jail.conf(5) findtime |
| `base/fail2ban.maxretry` | `int` | `5` | Failed attempts within findtime before an IP is banned, fail2ban jail.conf(5) maxretry |
| `base/ghostmirror.homelab_mirror` | `string?` | `"http://10.100.0.100:8090/archlinux/$repo/os/$arch"` | A homelab pacman mirror's URL ($repo and $arch as in a mirrorlist), put first on a homelab machine; default the lab's |
| `base/hardware.nvidia_driver` | `string?` | detected | NVIDIA driver branch: open (Turing on), 580xx (Maxwell to Volta), 470xx (Kepler), none (nouveau) |
| `base/networkmanager.untrusted_policy` | `string` | `"firewall-only"` | Off the home network: lockdown-tor closes inbound and lets out only tor, dhcp and tunnels until a VPN is up; firewall-only closes inbound and leaves egress open; off treats every network as home |
| `base/networkmanager.home_wired` | `bool?` | detected | Ethernet is always the home network and keeps its hardware MAC (a desktop); null detects it from the form factor |
| `base/networkmanager.wake_on_lan` | `bool` | `false` | Wake on a magic packet over ethernet (udev sets it on every wired link, NetworkManager leaves it) |
| `base/networkmanager.wifi_radio` | `bool?` | detected | Wi-Fi radio on at first boot; off on a desktop wired to the network, so only the link in use is up. Later toggles (toggle-wifi) persist in NetworkManager's own state; null detects it |
| `base/networkmanager.home_gateways` | `list<string>` | `[]` | Router MACs that make a network home, beside the admin's configs/secrets/keys/home-gateways |
| `base/networkmanager.homelab_dns` | `string?` | `"192.168.178.29"` | The homelab's split-horizon resolver, asked for homelab_domain out a home link (homelab machines); default the lab's router |
| `base/networkmanager.homelab_domain` | `string?` | `"lsck0.dev"` | The homelab's DNS zone |
| `base/networkmanager.homelab_subnets` | `list<string>` | `["10.100.0.0/24", "10.200.0.0/24", "10.250.0.0/24"]` | The homelab's subnets, routed straight out a home link and through wg0 elsewhere; default the lab's zones |
| `base/nftables.ssh_knock_window` | `string` | `"1h"` | How long a successful SSH port-knock keeps that IP allowed through to base/ssh.port, nft timeout syntax |
| `base/oomd.session_memory_low` | `filesize?` | detected | session.slice's MemoryLow, the desktop working set a build's reclaim keeps; null: 15% of RAM, 2 GiB max |
| `base/pacman.yay_cache_days` | `int` | `30` | Days an unused yay build cache dir may sit in $XDG_CACHE_HOME/yay before yay-cache-clean.timer deletes it, find -mtime argument |
| `base/pam.fido_origin` | `string` | `"pam://lsck0"` | FIDO2 origin and appid every enrolled key's mapping was made for (pamu2fcfg -o) |
| `base/smartd.test_schedule` | `string` | `"S/../.././02\|L/../../6/03"` | When smartd runs self-tests, smartd.conf(5) -s regex syntax (default: short test daily at 02:00, long test Saturday at 03:00) |
| `base/ssh.port` | `int` | `2222` | The port sshd listens on, reached through the port-knock (sshk, wake-pc, nftables, fail2ban) |
| `base/ssh.knock` | `list<int>` | `[9003, 7001, 8002]` | The three ports knocked in order to open the sshd port to that address (sshk, wake-pc, nftables) |
| `base/ssh.homelab_hosts` | `list<string>` | `["10.100.0.*", "10.200.0.*", "10.250.0.*", "192.168.178.29", "192.168.178.200"]` | ssh patterns of the homelab's guests, router and hypervisor: root, accept-new host keys from known_hosts.homelab (homelab profiles only); default the lab's zones, router and hypervisor |
| `base/ssh.wake_router` | `string?` | `"192.168.178.29"` | The always-on homelab router whose `wol-pc` wakes the desktop (wake-pc, homelab profiles only) |
| `base/ssh.wake_host` | `string?` | unset | The desktop wake-pc wakes and then ssh-es into |
| `base/tlp.charge_start` | `int` | `95` | Battery charge level below which charging starts (laptops whose firmware supports thresholds) |
| `base/tlp.charge_stop` | `int` | `100` | Battery charge level at which charging stops; 80 spares an always-plugged battery |
| `base/v4l2loopback.video_nr` | `int?` | detected | /dev/video<n> of the OBS virtual camera; null: a loaded one's, else the first free from 10, past webcams |
| `base/zram.compression_algorithm` | `string` | `"zstd"` | Compression used for the zram swap device, zram-generator.conf(5) compression-algorithm (a weaker CPU may prefer lz4) |
| `base/zram.swappiness` | `int` | `150` | How aggressively the kernel swaps to zram versus reclaiming page cache, sysctl(8) vm.swappiness (a zram swap favors higher than disk swap's usual 60) |
| `core/btop.accent` | `string` | `"c4"` | Palette slot for titles, highlights and the selection |
| `core/gnupg.cache_ttl` | `int` | `600` | Seconds gpg-agent caches a passphrase after use before re-asking, gpg-agent.conf(5) default-cache-ttl |
| `core/gnupg.cache_ttl_max` | `int` | `7200` | Seconds gpg-agent caches a passphrase at most, however often it is used, gpg-agent.conf(5) max-cache-ttl |
| `core/locale.lang` | `string?` | detected | LANG in /etc/locale.conf; detected: the one bootstrap set |
| `core/locale.formats` | `string?` | detected | Locale for dates, numbers, money, units, paper and addresses (every LC_ except CTYPE, MESSAGES, COLLATE and IDENTIFICATION); unset follows the language |
| `core/locale.keyboard_layout` | `string?` | detected | xkb layout of the console, X11 and the compositor; detected: the one bootstrap set |
| `core/locale.keyboard_variant` | `string?` | detected | xkb variant, e.g. nodeadkeys |
| `core/locale.keyboard_options` | `list<string>?` | detected | xkb options, e.g. ctrl:nocaps |
| `core/locale.wifi_country` | `string?` | detected | Wi-Fi regulatory domain (ISO 3166 alpha-2); detected: the country of the timezone, else the world domain |
| `core/nas.share` | `string` | `"//10.100.0.100/homelab"` | The homelab NAS's smb share mounted at /mnt/homelab (//host/share) |
| `core/starship.scan_timeout_ms` | `int` | `500` | Milliseconds starship waits for a directory scan (project file detection) before giving up, starship.toml scan_timeout |
| `core/syncthing.nas_address` | `string?` | `"tcp://10.100.0.100:22000"` | Address of the homelab NAS device (the lab's nas role); discovery is off, so this is how it is found |
| `core/trash.retention_days` | `int` | `1` | Days trash-empty.timer keeps a deleted file before purging it, trash-empty(1)'s days argument |
| `creating/obs.vaapi_render_node` | `string?` | detected | The /dev/dri render node the vaapi encoders use, by-path so it survives reboots |
| `creating/obs.canvas` | `string?` | detected | Canvas WxH: every profile's base and video output, and the Bare and VirtualCam collections |
| `creating/obs.mic` | `string?` | detected | The pipewire source node the Mic/Aux of the Streaming and Bare collections captures |
| `creating/obs.webcam` | `string?` | detected | The v4l2 device the VirtualCam collection's Camera captures, by-id so it survives replugging |
| `creating/obs.monitor_device` | `string?` | detected | The pipewire sink node obs monitors audio on |
| `creating/obs.record_encoder` | `string?` | detected | The recording encoder of the Recording and Streaming profiles |
| `creating/obs.stream_encoder` | `string?` | detected | The streaming encoder; h264 is what every ingest takes |
| `desktop/hyprland.monitors` | `list<record>?` | detected | One hl.monitor per output: output, mode, position, scale; detected from the connected outputs, any other output gets its preferred mode and an auto scale |
| `desktop/hyprland.main_monitor` | `string?` | detected | The output holding workspace 1, the bar's notifications, steam's toasts and the tablet; detected: the internal panel, else the largest, leftmost on a tie |
| `desktop/hyprland.workspaces` | `record?` | detected | Workspace to output; detected: the first ceil(10 / outputs) on the main monitor, the rest split over the others left to right |
| `desktop/hyprland.xwayland_scale` | `int?` | detected | GDK_SCALE for X11 apps (force_zero_scaling); detected: the main monitor's scale rounded, else 1 on a laptop and 2 elsewhere |
| `desktop/hyprland.app_workspaces` | `list<record>` | `[]` | Homes for apps by window class: {class, workspace, silent}; silent opens them without switching to their workspace or focusing them |
| `desktop/hyprland.pointer_sensitivity` | `float` | `0.0` | libinput pointer acceleration, -1 to 1 |
| `desktop/hyprland.natural_scroll` | `bool` | `false` | Touchpad content follows the fingers |
| `desktop/hyprland.idle_dim_s` | `int` | `900` | Idle seconds until the screens dim |
| `desktop/hyprland.idle_lock_s` | `int` | `1200` | Idle seconds until the session locks |
| `desktop/hyprland.idle_dpms_s` | `int` | `2100` | Idle seconds until the screens go off |
| `desktop/hyprland.idle_suspend_s` | `int` | `2400` | Idle seconds until suspend, unless an agent works or an inhibitor holds |
| `desktop/hyprland.idle_dim_saver_s` | `int` | `300` | Idle seconds until the screens dim in power saver (a laptop on battery) |
| `desktop/hyprland.idle_lock_saver_s` | `int` | `600` | Idle seconds until the session locks in power saver |
| `desktop/hyprland.idle_suspend_saver_s` | `int` | `1800` | Idle seconds until suspend in power saver |
| `desktop/mpv.ytdl_max_height` | `int` | `2160` | Max video height yt-dlp fetches for a stream (ytdl-format height filter, pixels); applies to mpv-stream, plain mpv runs no yt-dlp |
| `desktop/pipewire.app_loopbacks` | `bool` | `true` | Every app plays through a loopback of its own that carries its system volume, so a capture of the app (obs) stays at full level |
| `desktop/pipewire.eq_target` | `string?` | unset | The node.name of the headset sink the eq attaches to as a smart filter; unset, no eq chain |
| `desktop/pipewire.eq_preset` | `string` | `"pro-x-2.txt"` | AutoEq ParametricEQ preset for that headset, a file in this module or an absolute path |
| `desktop/plasma.kwin_outputs` | `bool?` | detected | Ship the committed kwin output layout; detected: on when a connected monitor's EDID is one it describes |
| `desktop/plasma.locale` | `bool` | `true` | Ship plasma-localerc with core/locale's language |
| `desktop/quickshell.pomodoro_focus_min` | `int` | `25` | Minutes of one focus block |
| `desktop/quickshell.pomodoro_break_min` | `int` | `5` | Minutes of the short break after a focus block |
| `desktop/quickshell.pomodoro_long_break_min` | `int` | `15` | Minutes of the long break after the last focus block of a round |
| `desktop/quickshell.pomodoro_cycles` | `int` | `4` | Focus blocks before a long break |
| `desktop/qutebrowser.search_url` | `string` | `"https://duckduckgo.com/?q={}"` | The default search engine, {} is the query; the homelab's searxng is reachable only on a homelab machine |
| `desktop/qutebrowser.search_method` | `string` | `"GET"` | GET or POST for the startpage's search form; most engines, the homelab's searxng too, take GET; POST works only in qutebrowser |
| `gaming/d2launcher.base_dir` | `string?` | detected | A Diablo II: Lord of Destruction install the game dir is seeded from; detected in the lutris prefixes |
| `gaming/d2launcher.resolution` | `string?` | detected | The monitor the render size derives from, WxH; detected from the focused monitor |
| `gaming/d2launcher.render_size` | `string?` | unset | The 4:3 size the game renders at inside gamescope, WxH; the monitor's full height by default |
| `gaming/gamemode.gpu_device` | `int?` | detected | The /dev/dri/cardN gamemode tunes while a game runs; none leaves the gpu alone |
| `gaming/gamemode.amd_performance_level` | `string?` | detected | The amdgpu power_dpm_force_performance_level during a game; high holds the clocks up, wasteful on battery |
| `gaming/lutris.dpi` | `int?` | detected | Logical dpi wine apps draw at under xwayland (LogPixels), 96 times the main monitor's scale |
| `gaming/mangohud.font_size` | `int` | `18` | MangoHud overlay text size in pixels, MangoHud.conf font_size |
| `gaming/pd2.game_dir` | `string?` | detected | The season 3 ProjectD2 dir; detected under ~/sync/games/d2 |
| `gaming/pd2.save_dir` | `string?` | detected | Season 3's single player saves (.d2s, plugy's .d2x and .sss); detected as Save beside the install |
| `gaming/pd2.s14_save_dir` | `string?` | detected | Season 14's single player saves and shared stash; detected as ~/sync/games/d2/Save-S14 when it exists |
| `llm/vllm.model` | `string` | `"RogerS-01/Josiefied-Qwen3-8B-abliterated-v1-AWQ"` | The hugging face repo vllm serves; an uncensored 4-bit AWQ build of Josiefied-Qwen3-8B-abliterated-v1 |
| `llm/vllm.model_revision` | `string` | `"0244c2514cc272a603368c0440ff3002143b2336"` | The model repo's commit, weights and tokenizer alike; bump from https://huggingface.co/api/models/<model>/revision/main |
| `llm/vllm.tool_call_parser` | `string` | `"hermes"` | vllm's tool call parser for the model's chat format (hermes for qwen3, gemma4 for gemma 4) |
| `llm/vllm.reasoning_parser` | `string` | `"qwen3"` | vllm's reasoning parser, which moves the model's thinking out of the reply into reasoning_content |
| `llm/vllm.gpu_memory_utilization` | `float?` | detected | The share of vram vllm takes; the rest stays for the desktop rendering on the same card |
| `llm/vllm.kv_cache_dtype` | `string` | `"fp8"` | fp8 halves the kv cache's vram use but has no native matrix support on RDNA3; auto (bf16) is faster there |
| `programming/android.avd` | `string` | `"nya35"` | Name of the emulator image made from the system image; empty makes none |
| `programming/cargo.sccache_redis` | `bool` | `false` | Compile through sccache with the homelab's shared redis cache (secret sccache.env); plain rustc whenever it is unreachable |
| `programming/claude.model` | `string` | `"claude-opus-5-5"` | The model every session starts on |
| `programming/claude.effort` | `string` | `"medium"` | Reasoning effort of that model |
| `programming/task.sync_url` | `string?` | unset | The taskchampion server every replica syncs with as the one client of configs/secrets/keys/taskwarrior-*; none: no sync |
| `programming/task.recurrence` | `bool` | `true` | This replica creates the instances of recurring tasks; one per sync, or each adds its own copy (task-sync(5)) |
| `programming/trmnl-claude.poster` | `bool` | `false` | This machine posts its Claude usage to the TRMNL panel; one poster per panel, a second would overwrite it |
<!-- options end -->
