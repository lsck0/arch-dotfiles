# Features

This is an unreviewed AI generated summary of dotfile features.

Everything below is set up by `dot sync` (`--no-push` does not commit) on a fresh machine; nothing is set by hand.
SUPER is the mod key. `dot plan --modules`, `dot set` and `hyprctl binds` list the modules, options and keybinds from
the tree itself; this file says what they do.

- [Install and the dot CLI](#install-and-the-dot-cli)
- [Machines, profiles and options](#machines-profiles-and-options)
- [Security and privacy](#security-and-privacy)
- [Networking](#networking)
- [Boot, power and system](#boot-power-and-system)
- [Hardware handling and detection](#hardware-handling-and-detection)
- [Desktop: Hyprland](#desktop-hyprland)
- [Desktop: quickshell](#desktop-quickshell)
- [Toggles](#toggles)
- [Theming and wallpapers](#theming-and-wallpapers)
- [Shell and terminal](#shell-and-terminal)
- [Apps and integrations](#apps-and-integrations)
- [MCP servers](#mcp-servers)
- [Programming and editors](#programming-and-editors)
- [LLMs](#llms)
- [Gaming](#gaming)
- [Creating](#creating)
- [LaTeX and research](#latex-and-research)
- [Virtualization](#virtualization)
- [Pentesting](#pentesting)
- [Backups and sync](#backups-and-sync)
- [Keybinds](#keybinds)
- [Options](#options)

## Install and the dot CLI

- `bootstrap.sh` from the Arch ISO hands over to `dot internal bootstrap`: all questions first, then disk, base system
  and the unattended chain; it also sets up a fresh WSL distro.
- `dotfiles-stage.service` runs `dot internal stage` once per boot until install and config are done, with no one at
  the keyboard.
- `dot sync`: the one command; pulls, runs migrations, installs, applies, backs up live app state, runs the
  gates, makes the signed `Generation: <n>` commit and pushes. `--no-push`, and a machine that does not sign, stop
  after the apply.
- `dot apply`: converges the machine without git: the system layer (an admin's) from the root-owned
  copy `/var/lib/dotfiles/repo`, then the user layer. `--system` and `--user` (or naming modules) run one layer alone.
  `--packages`: every declared package from the `[lsck0]` mirror, the user's flatpak and nix packages, then
  offers to remove packages no module declares.
- `dot plan`: what an apply would do, touching nothing; `--sandbox` also runs the user layer in a bubblewrap overlay
  and reports its write set; `--system` for the system layer; `--order` the run order, `--modules` every module.
- `dot status`: generation, last run, pending migrations and system parts, managed files changed since their apply, then
  every health check (failures, pending applies, drift, firewall, units, the [lsck0] snapshot, secrets due for rotation or
  a recovery drill) and the drift report each machine publishes into `configs/secrets/state/drift/<host>`; `--brief` the
  failures alone, for the login notice and the bar; `--json` all of it.
- `dot set`: every option off its default with value and source (default, platform, profile, detected); a module or
  `<module>.<option>` shows those; a value sets one, validated, stored in the profile (or `--machine` in the platform),
  applied as the option says (live, relink, relogin, reboot); `--default` resets it; `--json` is the schema, values
  and live state for a frontend (the settings window).
- `dot module adopt <file>`: carries a live edit of a managed copy back into the module's source, so the next apply
  keeps it. `unlink <module>` reverses a module's last apply (unchanged files, links and units go, originals come
  back); `remove <module>` also turns it off (`--machine` for the machine) and offers its packages for removal;
  `restore <module>` runs its restore verb.
- `dot rollback`: back to an earlier generation, undoing newer migrations; `--full` also takes the packages back (the
  `[lsck0]` snapshot and nixpkgs pin of that commit); `--dry-run` only reports what it would do.
- `dot theme [name|random]`: wallpaper and theme switching, fzf with previews without a name (see Theming).
- `dot secrets unlock|lock|init|seal`: the git-crypt `configs/secrets/` worktree behind the YubiKey; `--identity <age
  file>` without one. `dot secrets audit [rotated|drilled]`: what is due for rotation or a recovery drill, and recording
  it.
- `dot explain <path|package>`, `dot log [--trace]`: who wrote a path or declared a package, a run's records and span
  tree.
- `dot internal`: the plumbing other code runs, out of `dot --help`: `migrate` (`--system`, `--baseline`), `backup`
  (`--roundtrip` backs up, restores into an empty home and fails on any difference), `fetch file|git` (pinned
  downloads and checkouts), `prune <days>`, `gen` (`mirror/packages.txt`), `packages`, `watch` (every option and live
  state change as JSON lines), `theme get|list|apply`, `drift report|publish` (hourly), `audit remind`, `bootstrap`,
  `iso-install`, `stage` (the install chain), `iso` (the install iso), `complete <words>` and `completions zsh|nu`
  (installed by `base/dot`).
- `dot test lint`: static rules (module refs, layer rules, `~/sync` writes, stray files, platform facts and options,
  nu pitfalls, exec bits, palette clamps, generated files, locked flags, every `*.test.sh`/`*.test.nu`); `dot test
  check`: every formatter and linter (the sync gate); `dot test fmt` applies them.
- `dot test run`: the end-to-end VM test: a libvirt VM with secure boot in setup mode boots the ISO, `bootstrap.sh` is
  typed in, the chain installs on its own boots; `dot test drill egress|rollback`, `logs`, `shot`, `type`, `destroy`.
- A pkexec-only polkit action (`base/dot`) lets `dot set` from the settings window apply the system layer, asking the
  admin password every time.
- `FAILURES.*` at the repo root lists what failed in the last run; a login notification shows them
  (`failures-login.service`).
- `system-update`: confirm, then `dot sync --no-push`, flatpak, rustup, opam, ghcup, Hyprland plugins, tldr, nvim
  Lazy/Mason/treesitter and emacs package upgrades.

## Machines, profiles and options

- `platforms/<name>.nuon`: machine facts and the groups it installs (pc, notebook, wsl, server, vm);
  `platforms/<name>.options.nuon` holds machine-scoped option values.
- `profiles/<name>.nuon`: profiles picked at install (or `custom`, none), the one capability `secrets` (the owner: private submodule, accounts, keys, homelab) that gates modules, never a
  username check.
- Every module has an `enable` option; typed options (bool, int, string, list, record, filesize) carry docs, min/max,
  choices and an apply mode, and can be detected from the hardware when unset. Full list under [Options](#options).
- Groups: base, core, fonts, desktop, socials, latex, qemu, creating, gaming, programming, llm, rocm, pentesting; WSL
  gets base, core and programming.
- Skills: `skills/l-*` are symlinked into Claude Code, Copilot and Hermes skill dirs and registered with Gemini.
- `[lsck0]` package mirror: own pkgbuilds in `mirror/pkgbuilds` and AUR dependency fixes in `mirror/overrides.conf`,
  built by the homelab; pacman trusts it first, optionally pinned to a dated snapshot (`LSCK0_SNAPSHOT`).

## Security and privacy

### AppArmor and kernel

- AppArmor plus landlock, lockdown, yama, integrity and bpf LSMs on the kernel cmdline; policy cached in
  `/etc/apparmor/earlypolicy` so it loads before the first unit.
- apparmor.d profiles in complain by default; everything that opens outside content is enforced (`profiles.conf`):
  browsers, mail and chat, media and document viewers, archive and media tools, obsidian, zotero, qbittorrent, the
  MCP servers for blender and obs, the child openers.
- 17 own profiles (`profiles/`) plus `local/` drop-ins; after loading, the modes are compared with the expected ones
  and the run fails on a mismatch.
- `aa list|enforce|complain|off <profile>`: per-machine overrides that config runs leave alone.
- KSPP cmdline (`slab_nomerge init_on_alloc=1 init_on_free=1 randomize_kstack_offset=on vsyscall=none
  page_alloc.shuffle=1`); `nosmt` on affected Intel CPUs unless `base/boot/hardening.allow_smt`.
- sysctl hardening (`kptr_restrict`, `kexec_load_disabled`, `bpf_jit_harden=2`, protected fifos/regular/links,
  `suid_dumpable=0`, no ICMP redirects, `tcp_rfc1337`); ptrace_scope stays 1 for pwntools.
- Rare protocols and filesystems blacklisted: dccp, sctp, rds, tipc, cramfs, freevxfs, jffs2, hfs, hfsplus, firewire.
- RAPL powercap readable by wheel only (CVE-2020-8694).
- pacman hooks strip setuid from capture tools and give them file caps under the wireshark group.

### Disk encryption, TPM, YubiKey, secure boot

- LUKS root unlocks with TPM2 plus PIN, then YubiKey FIDO2, then passphrase (`sd-encrypt`, PCR 7 and 15); missing
  enrollments print the exact `systemd-cryptenroll` command.
- Other fixed LUKS partitions get crypttab entries with discard and no workqueues; the root LUKS header is backed up to
  `configs/secrets/` (`header-backup.nu`).
- Remote unlock (`base/boot/remote-unlock.ssh_unlock`): wake-on-lan, then ssh into the initramfs (tinysshd on 2223)
  to type the passphrase.
- Secure boot with sbctl: own keys (plus Microsoft's unless the platform says own only), enrolled in setup mode with
  TPM event log OpROM hashes; UKIs, systemd-boot and fwupd's EFI binary signed.
- Unified kernel images for `linux` and `linux-lts` (fallback) with the cmdline embedded; loader editor off.
- YubiKey: pcscd, udev and polkit rules for wheel, `totp [account]` copies an OATH code, the ssh-sk stub, sops age
  keys merged from secrets.
- PAM: sudo and polkit accept a YubiKey touch (no PIN) or a fingerprint when enrolled; the quickshell lock
  has a password stack and a YubiKey-only stack.
- sudo for wheel with a password, never NOPASSWD except two validated drop-ins (the VPN namespace runner and the games
  group).
- Secrets: a git-crypt submodule unlocked by a YubiKey touch (`dot secrets unlock`), age-sealed key, recovery drill
  reminders (`recovery-drill.timer`).

### Firewall

- nftables `table inet fw`, resting state `fw-lockdown`: only loopback, established, on-link NDP and container/VM
  bridges; a home link or `toggle-firewall` lifts it to `fw-inbound`.
- `fw-inbound`: input drop, ICMP rate limited, KDE Connect, LocalSend and mDNS only on home links; sshd on 2222 opens
  for an hour after a port knock (9003, 7001, 8002).
- Pentest VPN interface `tun0` reaches only listener port ranges (4444-4460, 8000-8099, 9001, 9443).
- `fw-egress` kill switch off the home network: output drop except tunnels, DHCP, tor's uid, tunnel fwmarks, the games
  bypass mark and a timed captive-portal window.
- endlessh tarpit on port 22 as a decoy; fail2ban bans sshd failures on 2222 through nftables.

### Untrusted networks, VPN and tor

- Home detection by gateway MAC (never SSID) with the hardware MAC kept; everywhere else a random MAC per connect, no
  hostname in DHCP, IPv6 privacy addresses.
- `base/networkmanager.untrusted_policy`: `lockdown-tor` (inbound closed, egress only through tor until a VPN is up,
  avahi and IPv6 off), `firewall-only` (default) or `off`.
- `auto-vpn.service`: ProtonVPN off on a home network, on everywhere else, with backoff retries.
- `protonvpn` network namespace with a fail-closed WireGuard tunnel; `vpn <cmd>` runs a command inside it, and
  yt-dlp, mpv streaming, ani-cli, gallery-dl, spotdl and nicotine are shimmed to always run there.
- tor transparent proxy (`tor-router`): all TCP and DNS through tor with exemptions for tunnels, home LAN and guests;
  `toron`/`toroff` and `toggle-tor`.
- `toggle-anonymous-socks`: a separate tor with a pool of isolated SOCKS ports, each verified as tor, a round-robin
  proxychains config, NEWNYM, optional rate cap and TTL persona.
- Portmaster application firewall with DoT to Cloudflare and filter lists (trackers, malware, ads); a bypass for
  loopback, pentest and libvirt traffic.
- WireGuard `wg0` to the homelab from a secrets file (`toggle-vpn`); homelab subnets route straight out at home and
  through wg0 elsewhere.
- qbittorrent is bound to the VPN interface `proton0`.

### Browser and app privacy

- Firefox and Chromium policies: telemetry, studies, sponsored content and sync off, HTTPS-only, third-party cookies
  blocked, WebRTC limited to the default interface, no prefetch, uBlock forced.
- Every tool's telemetry opt-out set in the environment (`no-telemetry.conf`, 18 variables) and in app configs
  (VSCodium, Zed, gemini, bruno, syncthing, jdownloader, ollama, MCP servers).
- Thunderbird: remote images blocked, no User-Agent, external GnuPG.

### Sandboxing and monitoring

- `sandbox-build [-w dir] -- cmd`: a transient unit without network, read-only home and system, private tmp.
- `confine -- cmd`: a GUI app in `confined.slice` with kernel, cgroup and clock protection.
- `pentest <cmd>`: runs a tool in the `pentest` group whose sockets bypass Portmaster.
- OSSEC HIDS on the auth journal, alerts readable by admins and shown in quickshell.
- `lynis-audit.timer` monthly; `update-check.timer` daily with arch-audit advisories; `system-notify` notifies on
  failed system units, smartd warnings and health reports.
- `failure-notify@`: a critical notification for every failed user unit; `oom-notify` for every oomd or kernel OOM
  kill.
- `gitleaks protect --staged` as a global git pre-commit hook.

## Networking

- NetworkManager with systemd-resolved: Quad9 over opportunistic DoT, DNSSEC allow-downgrade, LLMNR and mDNS off in
  resolved (avahi does mDNS).
- Connectivity check off on home links (split-horizon DNS), on elsewhere.
- Homelab split DNS for its domain and routes for its subnets on home links (homelab machines).
- ModemManager only when a modem exists.
- Ethernet on a desktop keeps its MAC and wake-on-lan (`base/networkmanager.home_wired`); `wake-pc` wakes the desktop
  through the homelab router and ssh-es in.
- `sshk`: knocks, waits for 2222, then ssh with the secrets key or the YubiKey; sshd is key-only, wheel-only, no root.
- Printing: driverless printers found over mDNS get permanent queues (`printers-sync`), plus a cups-pdf "PDF" queue.
- Timezone follows the IP location on home networks only and never with a VPN or tor up (`timezone-auto`).
- Mirrorlist ranked weekly and rebuilt monthly by ghostmirror; the homelab mirror goes first when it answers.
- KDE Connect and LocalSend ports open on home links; `toggle-wifi`, `toggle-ethernet`, `toggle-offline`.

## Boot, power and system

- systemd-boot, timeout 1, UKIs; plymouth `cyberpunk` theme; ly display manager on tty2 with a themed console palette,
  F4 reboots into firmware setup.
- zram swap (zstd, size of RAM), MGLRU, swappiness 150.
- systemd-oomd kills in `app.slice` under pressure; `session.slice` keeps `base/oomd.session_memory_low` and CPU weight
  400 so the desktop stays responsive.
- Apps launch into their own `app.slice` scopes through `uwsm-app`; helpers into `background-graphical.slice`.
- I/O schedulers per device type (none for NVMe, mq-deadline for SSD, bfq for HDD).
- sched_ext `scx_lavd --autopower` on laptops.
- TLP: battery limits on laptops (`base/tlp.charge_start`, `charge_stop`), low-power profile on battery.
- Journal capped at 500M; cores kept 7 days; the last panic log saved by pstore.
- `home-sweep.timer` trims app logs weekly; `trash-empty.timer` empties trash older than a day; `nix-gc.timer`;
  `yay-cache-clean.timer`.
- smartd: nightly short and weekly long self-tests on every disk.
- fwupd metadata refresh only; updates stay manual.
- `$HOME` stays clean: XDG env vars in `app-dirs.conf`, 56 dot dirs and files reclaimed as symlinks and 9 moved under
  XDG, lowercase user dirs.

## Hardware handling and detection

- NVIDIA driver branch detected from the PCI id (`base/hardware.nvidia_driver`: open, 580xx, 470xx, none).
- Monitors, main monitor, workspace layout and XWayland scale detected from the outputs (`desktop/hyprland.*`).
- Keyboard layout, variant and options from the bootstrap locale; Wi-Fi regulatory domain from the timezone.
- Fan curve for the X870E AORUS ELITE board via it87, regenerated every boot for the current hwmon numbering.
- Validity fingerprint readers through python-validity, restarted on resume.
- SZ PENG YI T1161 graphics tablet: own userspace driver with pressure, express keys as F13 to F24, calibration.
- DDC monitor brightness over i2c-dev; LACT for GPU control; thermald on Intel.
- OBS virtual camera on a fixed `/dev/video<n>` (`base/v4l2loopback.video_nr`).
- Keyboard backlight restored on boot; AQ_DRM_DEVICES pinned to the boot GPU when all outputs hang off it.
- gamemode GPU and lutris DPI detected from VRAM and monitor scale; vllm VRAM share from the GPU.
- ROCm groups for `/dev/kfd` only when an AMD GPU exists.
- Modules skip themselves on WSL, without the hardware, or outside their form factor.

## Desktop: Hyprland

- Hyprland configured in Lua (`hl.*`), started by uwsm from ly; Plasma available as the second session.
- Keybinds: see [Keybinds](#keybinds) and the generated table.
- Window rules: translucent terminals and chat, floating file pickers, pavucontrol, mission center and dolphin at
  1080x720, Steam toasts pinned to the main monitor, Unreal child windows floating.
- Workspaces split across monitors (`desktop/hyprland.workspaces`); app homes by class
  (`desktop/hyprland.app_workspaces`).
- Idle chain from options: dim at 15 min, lock at 20, screens off at 35, suspend at 40; in power saver (a laptop on
  battery) dim at 5, lock at 10, suspend at 30. Suspend waits while an agent works or an inhibitor holds.
- Idle guards: no sleep while media plays, an SSH session is open, or a coding agent is mid-turn (`agent-guard`).
- Lock through quickshell, hyprlock as fallback; lid close locks even while the lid switch is inhibited.
- Screen shaders (`toggle-shader`): colorblind correction and simulation, false color, smart invert, vivid,
  composition grid, cyberpunk.
- Color grading through the display CTM (`color-grading`): presets default, reading, grayscale, night light
  and software brightness; night light resets at reboot.
- Power saver turns off animations, blur, shadows, shaders and dynamic cursors.
- hypr-dynamic-cursors plugin (shake to find) via hyprpm.
- Desktop mascots (wl_shimeji) on `SUPER+y`.
- GPG on the clipboard: `gpg-clip decrypt|encrypt|sign` on `SUPER+SHIFT+d/x/c`; plaintext shown in a pager, never
  copied.

## Desktop: quickshell

One quickshell process draws the bar, panels, launcher, notifications, OSD, lock and wallpaper; each part answers
`quickshell ipc call <target> <fn>`.

### Bar

- Main screen: app menu and workspaces left; clock, weather, media, OBS and Discord center; tray, agents, homelab,
  system, network, display, audio, notifications, keyboard layout, indicators and exit right. Other screens: app menu
  and workspaces.
- Drawers open on hover, one at a time; `quickshell ipc call bar open|close|toggle <panel>`.
- Clock: calendar, time zones, a time-travel slider, reminders and pomodoro.
- Weather: wind, next 24 hours, 3-day forecast, animated radar, alerts; location from geoclue, timezone or IP, or
  pinned (`toggle-weather-location`).
- Media: seek, shuffle, loop, per-player volume, pin a player; clicks pause, skip, go back.
- OBS: go live, record, pause, switch scenes, mute inputs, stream and dropped-frame stats.
- Discord: voice channel participants, mute, deafen, leave (also `SUPER+m`).
- Agents: Claude Code session and weekly limits, tokens and messages today and this week.
- Homelab: status, alerts, hosts, storage, traffic, services; connect the homelab VPN.
- System: CPU, memory, GPU and temperature with history, top processes, OSSEC alerts, power mode selector, disk speed
  test.
- Network: details, throughput, Wi-Fi list with password entry, tunnel switches (ProtonVPN, homelab VPN, tor,
  anonymous SOCKS), radios (Wi-Fi, Ethernet, mobile, Bluetooth, offline), a firewall mode picker (permissive, default,
  restrictive), speed test, Wi-Fi QR share.
- Display: brightness per monitor (backlight or DDC), color grading presets, night light, shaders, monitor layout
  (extend, mirror, off) and scale.
- Audio: output and input devices, fader and meters, per-app routing, "heard by", deafen, qpwgraph.
- Notifications: history, clear, do not disturb (middle click toggles).
- Indicators: doctor findings (click runs the check), keep awake, reminders, pomodoro; tray with pin and hide per icon.
- Keyboard layout: click cycles the xkb layout.

### Panels and overlays

- Settings window (`SUPER+comma`): every module's options from `dot set --json`, searchable, typed rows (bool,
  choice, number, list, path picker); `dot set` live or queued with apply and revert; offers the admin system apply
  when needed; quick toggles from `status.nu`.
- Tasks and notes (`SUPER+o`): taskwarrior pending list with filter, add in task syntax, done, start, delete; the notes
  pad `~/sync/notes/notes.md`; due-soon and overdue notifications.
- Desktop widgets: an agenda card (reminders and tasks, click opens the tasks panel), a notes card editing the same
  file in place, a pomodoro card while a phase runs.
- Launcher (`SUPER+d`): apps by fuzzy and frecency score; `=` calculator (qalc, Enter copies), `>` run a command, `@`
  windows, `:` clipboard.
- Clipboard (`SUPER+v`): text and image history (500 entries, runtime dir only), skips password manager entries;
  copy, open, forget, clear.
- OSD: volume, mic, brightness, keyboard backlight and app launch on the focused output.
- Notifications: toasts fold per app, hover pauses, critical stays; history of 30; DND persists and turns on while OBS
  runs.
- Overview (`SUPER+Tab`): live window previews per workspace and monitor, alt-tab style cycling.
- Power menu (`SUPER+SHIFT+e`): lock, exit, suspend, shutdown, reboot, firmware setup; the last three ask first.
- Lock (`SUPER+Escape`): password, or `Ctrl+K` for YubiKey with PIN; ASCII-art wallpaper, clock, media, stats, a
  notification dock without content; relocks after a quickshell restart.
- Wallpaper picker (`SUPER+w`): wallpapers that fit the largest screen with a palette preview, or the themes; Enter
  runs `dot theme <name>`.
- Reminders: minutes and a message become a systemd user timer; presets; snooze 5 or 15 minutes from the alert card.
- Pomodoro: focus blocks with pause, skip, stop; focus, break and long break lengths and the cycle count are options.
- Internet speed test (fast.com), disk speed test (direct I/O), Wi-Fi QR code with the password shown on demand.
- Background: the wallpaper with a reveal and palette crossfade on every switch.

## Toggles

`scripts/toggles/toggle-<name>.nu` with `on|off|toggle|get|label`; `SUPER+t` (menu), the bar drawers and the settings
window list them through `status.nu`. Privileged halves go through `pkexec toggle-root` with polkit rules for wheel.

- `anonymous-socks`: tor SOCKS port pool with persona and rate cap; `check`, `newnym`, `proxylist`, `proxyconf`.
- `bluetooth`, `wifi`, `ethernet`, `mobile`: radios and devices through bluetoothctl and nmcli.
- `color-grading`: cycles the CTM presets; `set <preset>`.
- `dnd`: quickshell do not disturb.
- `docker`, `ollama`, `oom-protection`, `tor`, `vllm`: start or stop the service.
- `firewall`: permissive (no inbound table, Portmaster off), default (inbound plus Portmaster), restrictive (lockdown
  plus Portmaster), cycled in that order; the network panel picks one directly.
- `focus`: DND, keep awake, night light and grayscale together; off restores the previous states.
- `font`: UI font family across terminals, editors, browsers, GTK, KDE and quickshell; `set`, `set-size`, shortlist.
- `keep-awake`: a sleep and idle inhibitor.
- `monitor-scale`: steps the scale and stores it with `dot set --machine`; `live`, `layout extend|off|mirror`.
- `nightlight`: 4000K white point.
- `obs-listen`: hear the OBS stream mix instead of the system audio (stream inputs monitored, per-app paths muted).
- `offline`: networking and radios off, tunnels down; off restores them.
- `powermode`: auto, balanced, performance or power saver through TLP, and power saver in Hyprland, ghostty and
  quickshell.
- `protonvpn`: connect with the kill switch, Portmaster paused meanwhile.
- `shader`: a Hyprland screen shader or off; `set`, `list`.
- `theme-mode`: flips the theme to its light or dark pair; `light`, `dark`, `set`.
- `vpn`: homelab WireGuard `wg0`.
- `weather-location`: pin the current coordinates or go back to automatic.

## Theming and wallpapers

- `dot theme <name|path>`, `dot theme random`, `dot theme` (fzf with previews), `SUPER+w` (picker), nsxiv `w`.
- 34 hand-made palettes (ayu, catppuccin, dracula, everforest, gruvbox, kanagawa, monokai, night-owl, nord, one,
  rose-pine, solarized, tokyo-night, void), most families with a light and some with a soft variant, which the
  light/dark toggle flips between; a wallpaper named in a palette uses it and its font, any other wallpaper
  gets a palette from wallust.
- `palette.nu` enforces WCAG contrast and background clamps for every consumer; quickshell mirrors it.
- Theme verbs recolor live: Hyprland borders, quickshell, GTK 3/4 (oomox), KDE colors, kitty, ghostty, konsole, tmux,
  herdr, nvim (every running instance), emacs, VSCodium, Zed, btop, yazi, zathura, sioyek, qutebrowser, Firefox
  (pywalfox), Thunderbird, Spotify (spicetify), Discord (BetterDiscord), Steam (Millennium), caido, ghidra, gh-dash,
  hermes, telegram palette, delta.
- `toggle-font` switches the UI and terminal font family everywhere.
- Wallpapers fit-checked per monitor (`wallpaper-list`), private ones imported into `configs/secrets/`
  (`wallpaper-import`).

## Shell and terminal

- zsh with oh-my-zsh libs and plugins, fzf-tab, autosuggestions, syntax highlighting, starship (git state, worktree,
  languages, duration); nushell configured to match.
- Behavior changes: `rm` is trash, `cat` is bat, `ls` is eza, `cd` is zoxide, `pacman` sudo only for changes,
  `git clone` recurses submodules, `kubectl` is kubecolor.
- `fence <cmd>`: a heavy build at the lowest priority and pinned off the V-Cache CCD.
- tmux (prefix `C-q`), vi copy mode, OSC 52, tmux-fingers, autoreload, popups: btop, lazydocker, gh-dash, lazyjj, k9s,
  lazysql, lazyjournal, rustnet, netscanner, taskwarrior-tui, toggles, wtree, pclone, tms.
- herdr multiplexer with the same prefix and popups; `herdr-open <dir>` lays out nvim, claude and zsh tabs; `hms`
  picks a project; prefix `o` is `herdr-fingers` (pick a url, path, hash or ip off the pane: enter copies, ctrl-o
  opens). tmux-fingers' jump mode is prefix `O`.
- ghostty as a resident D-Bus service for instant windows; kitty as the fallback.
- yazi with `g h`, `g c`, `g p` jumps.
- `wtree` (git worktrees), `pclone` (clone into ~/projects and open), `git-sync` (pull and push every repo),
  `extract` (safe archive extraction with size and path limits), `picker` (themed bemenu).
- `task-dashboard`: taskwarrior, timewarrior, GitHub issues and agent task dbs in one TUI.
- About 60 CLI tools (fd, fzf, ripgrep, dua, gping, trippy, procs, ouch, croc, ...).

## Apps and integrations

- Firefox: policies above, uBlock, pywalfox, Privacy Badger, SearXNG on homelab machines, the local startpage as new
  tab, Ctrl+V outside a text field pastes into the URL bar.
- qutebrowser: adblock, search aliases (ddg, g, aur, gh, w, yt, ...), `J`/`K` tabs, palette from wallust.
- Chromium: managed policy, uBlock Origin Lite and browserpass forced.
- Thunderbird, Signal, Telegram, Element, Discord (BetterDiscord with pinned plugins, voice status in the bar),
  ZapZap, hexchat, Proton Mail and Meet, TeamSpeak (native Wayland).
- Spotify patched with spicetify (theme, ad and telemetry blocking), confined by AppArmor; spotify_player in the
  terminal.
- mpv (gpu-next, MPRIS), zathura and sioyek with synctex back to nvim, okular, bookokrat,
  nsxiv (`d` trashes, `w` sets wallpaper).
- PipeWire: an AutoEq headset EQ (`desktop/pipewire.eq_target`, `eq_preset`).
- LibreOffice and OnlyOffice; obsidian with a local REST API; feather Monero wallet in `~/sync`; JDownloader quiet;
  gparted through pkexec.
- About 120 own desktop entries (TUI apps open in ghostty); `desktop-run` adds file pickers, group switching and
  `--notify` on an early exit.
- Proton Pass, `pass` synced through `~/sync`, VeraCrypt vault `~/sync/vault.hc` (`veracrypt-vault`).
- Homelab notifications from ntfy as desktop notifications (alert groups update and resolve in place).

## MCP servers

Registered in `~/.claude.json` by the module that owns the app; each listens on loopback or runs over stdio.

- `playwright`, `playwright-firefox` (headless isolated browsers), `chrome-devtools` (programming/playwright).
- `postgres-mcp` (own role, read-only), `docker` (docker group only), `kubernetes` (with a kubeconfig), `grafana`
  (homelab, read-only).
- `godot-mcp`, `unreal-mcp` (editor plugin on 127.0.0.1:8766).
- `blender-mcp`, `inkscape-mcp`, `openscad`, `audacity`, `obs-mcp` (creating group).
- `obsidian-mcp` (local REST API), `zotero-mcp` (local API, no cloud key).
- `caido-mcp`, `ghidra-mcp`, `metasploit` (no dangerous actions), `wireshark-mcp`, `zap-mcp`, `semgrep`, `sliver`
  (pentesting group).

## Programming and editors

- Neovim (lazy.nvim, locked): LSPs, formatters and DAP adapters for about 40 languages through mason, blink.cmp,
  telescope, conform, nvim-dap, neotest, gitsigns, fugitive, diffview, octo, jj.nvim, orgmode, kulala, molten, dadbod,
  vimtex, lean.nvim, taskwarrior and claudecode.nvim.
- Emacs with evil and an `SPC` leader that mirrors nvim, eglot, magit, dirvish, auctex, claude-code.el.
- VSCodium (vim, telemetry off, palette colors), Zed (vim, Pywal theme), JetBrains Toolbox, neovide.
- Claude Code: model and effort options (`programming/claude.model`, `effort`), agent-guard hooks, rtk output
  condensing, caveman plugin, skills linked; Copilot CLI, Gemini CLI and Hermes agents with the same skills.
- Toolchains: gcc, clang, zig, odin, go, rust (35 cargo tools, mold linker), node, bun, deno, dotnet, java, haskell
  (ghcup), ocaml (opam), lean (elan nightly), jai, typst, emscripten.
- Android (`programming/android`): android-ndk and jdk21 from pacman, a user-writable SDK in
  `~/.local/share/android-sdk` from the pinned cmdline-tools (platform-tools, build-tools 35.0.1, android-35, the
  emulator and its google_apis x86_64 image), an emulator AVD (`programming/android.avd`); state kept out of
  `~/.android`.
- Debugging and profiling: gdb with pwndbg and debuginfod, cgdb, lldb, rr, nnd, bpftrace, heaptrack, hotspot, samply,
  tracy, valgrind, renderdoc.
- Verification: kani, flux, apalache, cbmc, tla+, z3; math: sage, gap, macaulay2, R.
- git: delta, mergiraf, zdiff3, jj, lazygit, git-lfs; GitHub through `gh` with the token from secrets; gh-dash themed.
- taskwarrior synced with a taskchampion server every 10 minutes (`programming/task.sync_url`), timewarrior hook,
  GitHub issues pulled by bugwarrior.
- Docker (system socket, no implicit group), images and build cache older than a week pruned with the daemon; podman
  and distrobox rootless; kubernetes tools and minikube.
- PostgreSQL with a role and database per admin; SQLite tools.
- nix (flakes) with a low-priority daemon; devenv through direnv; per-repo `.identity` dirs (`identity-init`).
- Godot, Unreal Engine (from `~/sync/vendor`), Bruno, HTTP tools, terraform, aws and stackit CLIs.
- TRMNL panel showing Claude usage (`programming/trmnl-claude.poster`).

## LLMs

- ollama on 127.0.0.1:11434, socket activated, idle exit after 30 min, pinned models (`ollama-ensure-models`).
- vllm on ROCm (`llm/vllm.model`, `model_revision`, `gpu_memory_utilization`), socket activated on 127.0.0.1:8000:
  Josiefied-Qwen3-8B-abliterated as 4-bit AWQ, tool calls through the hermes parser and thinking split out by the
  qwen3 reasoning parser (`tool_call_parser`, `reasoning_parser`).
- Alpaca seeded with both local backends; llmfit, heretic-llm.
- gamemode stops vllm and ollama during a game and brings them back.

## Gaming

- Steam with Millennium (cyberpunk theme, palette), launch options `gamemoderun mangohud %command%` added to installed
  games, MangoHud and OBS capture on.
- Steam and games bypass the VPN through the `games` group's fwmark and the physical route.
- GE-Proton and Proton-LayeredOverlay pinned; proton-cachyos, gamescope, protontricks, vkd3d.
- gamemode: renice, core pinning, GPU performance level, split-lock mitigation off during a game.
- MangoHud hidden at start, `Shift_R+F12` toggles; vkBasalt CAS and SMAA, `Home` toggles.
- FFXIV through XIVLauncher with Dalamud plugins restored from backups; Lutris with wine DPI from the monitor scale.
- Diablo II with Median XL through d2launcher (pinned), seeded from a lutris install, rendered 4:3 in gamescope
  (`gaming/d2launcher.*`).
- Modrinth with saves in `~/sync/minecraft`; Heroic, CurseForge, r2modman, Path of Building, emulators, nethack.
- VR: WiVRn, OpenComposite, WayVR.

## Creating

- OBS: Recording, Streaming and VirtualCam profiles rendered from options (canvas, encoders, mic, monitor device), VAAPI
  encoders detected; replay buffer on `SUPER+F9`. The stream scales to 1080p60 for Twitch while the canvas and the
  recording keep full size. Collections: Streaming (stream and record), VirtualCam (desktop plus the webcam, one scene
  per corner, Desktop without it), Bare (desktop and all audio).
- Blender with the MCP bridge (`blender-mcp-bridge`); GIMP with PhotoGIMP; Krita with a prebuilt resource cache;
  Inkscape, OpenSCAD, Audacity with mod-script-pipe.
- kdenlive, handbrake, lmms, aseprite, tiled, rawtherapee, xournalpp, gpu-screen-recorder.

## LaTeX and research

- TeX Live, tectonic, latexmk with synctex and sioyek as previewer; `synctex-edit` jumps back into the running nvim.
- Zotero with the local API on; zotero-mcp; bibiman.

## Virtualization

- libvirt with qemu-full and GNOME Boxes, nested virtualization, a non-colliding default network, admin prompt for
  `qemu:///system`.
- Waydroid with pinned LineageOS images, freeform windows, device permissions tightened after a session.
- podman and distrobox rootless.

## Pentesting

- Tools in the `pentest` group bypass Portmaster; `pentest <cmd>` enters it.
- caido (plugins restored, themed), ZAP with the MCP add-on, ghidra (themed, MCP extension), metasploit (db, rpcd on
  loopback, autoscan rc), wireshark and tcpdump without sudo via file caps, nuclei, rustscan, netscanner, seclists at
  `~/.wordlists`, pinned LLM jailbreak and prompt-injection corpora in `~/.local/share/llm-jailbreaks`, proxychains
  with the anonymous SOCKS pool, sliver, semgrep.
- A CLI toolkit grouped in `pentesting/toolkit`.

## Backups and sync

- Config in git; app state in the private submodule, `configs/secrets/keys/<app>/` (git-crypt) or
  `configs/secrets/state/<app>/`, written by `dot sync`'s backup and restored by each module's link.
- syncthing: `~/sync` with the NAS (30 day versioning), announce, relays and NAT off; GUI password from secrets.
- NAS share at `/mnt/homelab` (automount, sealed SMB 3.1.1) on home or wg0; `~/nas` symlink.
- `dot rollback` for generations.
- App state round trips: Claude, gh token, OBS collections, FFXIV and Dalamud, Modrinth, caido, Plasma, Spotify prefs.

## Keybinds

The Hyprland binds live in `hyprland_keybindings.lua`; every bind carries a `description`, so `hyprctl binds` lists
them all. Most used:

| keys | action |
|---|---|
| `SUPER+Return` | terminal |
| `SUPER+d` | app launcher |
| `SUPER+Q` | close the window |
| `SUPER+h/j/k/l` | focus; with `SHIFT` move, with `CTRL` move into a group |
| `SUPER+1..0` | workspace; with `SHIFT` move the window there |
| `SUPER+Tab` | overview |
| `SUPER+space`, `SUPER+f` | float, fullscreen |
| `SUPER+R` | resize mode |
| `SUPER+v` | clipboard history |
| `SUPER+o` | tasks and notes |
| `SUPER+comma` | settings window |
| `SUPER+t` | toggles menu |
| `SUPER+w` | wallpaper picker |
| `SUPER+Escape` | lock |
| `SUPER+SHIFT+e` | power menu |
| `SUPER+SHIFT+s` | region screenshot |

### Inside quickshell panels

- Tasks: `j`/`k` or arrows move, `g`/`G` first and last, `Enter` or `d` done, `s` start or stop, `x` or `Del` delete,
  `a`/`i` add, `/` filter, `Tab` notes, `Esc` clears the filter then closes.
- Settings: type to search, `Tab` switches pane, arrows move and adjust, `Enter` toggles, steps or edits, `Ctrl+S`
  applies the queue, `Ctrl+Z` reverts it, `Ctrl+R` resets an option, `Ctrl+O` browses a path, `Esc` backs out.
- Launcher: type to filter, arrows and `PgUp`/`PgDn` select, `Enter` runs, copies or focuses, `Esc` clears then
  closes.
- Clipboard: type to filter, `Enter` copies, `Alt+Enter` opens, `Del` forgets, `Shift+Del` clears all.
- Wallpaper picker: `Left`/`Right` or `Tab` browse, `Up`/`Down` switch wallpapers and themes, `Enter` applies, type
  to filter.
- Overview: arrows and `Tab` move, `1..0` jump to a workspace, `Enter` goes, `Esc` closes.
- Power menu: `L` lock, `E` exit, `H` suspend, `S` shutdown, `R` reboot, `F` firmware; `Y` confirms.
- Lock: `Enter` submits, `Ctrl+K` security key mode, `Esc` back or clear.
- Reminders: minutes, `Enter`, message, `Enter`; speed tests: `Enter` runs again; `Esc` closes every overlay.

### Terminal and editor

- tmux and herdr prefix `ctrl+q`; tmux `v`/`s` split, `q` kill pane, `e` copy mode, `M-H/J/K/L` panes; popups as in
  [Shell and terminal](#shell-and-terminal).
- nvim leader is space: `f` find, `l` lsp, `d` debug, `n` test, `j` jupyter, `p` profiling, `s` search/replace, `g`
  git, `k` keys/secrets, `t` trouble, `T` taskwarrior, `q` session, `c` claude, `C` comment/doc, `o` github, `m`
  orgmode, `r` rest, `u` undotree, `U` unreal.
- VSCodium and Zed: `alt+1..5` editor N, `alt+c` new file, `alt+x` close.
- MangoHud `Shift_R+F12`, vkBasalt `Home`, sioyek `i`/`o`, zathura `r`/`R`/`i`, qutebrowser `J`/`K`/`alt+x`.

## Options

Every typed option besides `enable` (`dot set` shows values and sources and changes one). Detected means
the value comes from the hardware or system when the platform and profile leave it unset.

| option | type | default | what it does |
|---|---|---|---|
| `base/boot/hardening.allow_smt` | `bool` | `false` | Keep hyperthreading despite MDS/MMIO, accepting the cross-sibling leak for the threads |
| `base/boot/remote-unlock.ssh_unlock` | `bool` | `false` | Wake-on-lan this machine, then ssh into the initramfs to unlock LUKS remotely |
| `base/boot/remote-unlock.wifi` | `bool` | `false` | Also join the home wifis (configs/secrets/keys/wifi) in the initramfs; their keys are written into the image |
| `base/ghostmirror.homelab_mirror` | `string?` | unset | A homelab pacman mirror's URL ($repo and $arch as in a mirrorlist), put first on a homelab machine |
| `base/hardware.nvidia_driver` | `string?` | unset | NVIDIA driver branch: open (Turing on), 580xx (Maxwell to Volta), 470xx (Kepler), none (nouveau) |
| `base/networkmanager.untrusted_policy` | `string` | `"firewall-only"` | Off the home network: lockdown-tor closes inbound and lets out only tor, dhcp and tunnels until a VPN is up; firewall-only closes inbound and leaves egress open; off treats every network as home |
| `base/networkmanager.home_wired` | `bool?` | detected | Ethernet is always the home network: it keeps the hardware MAC and wake-on-lan (a desktop); null detects it from the form factor |
| `base/networkmanager.wifi_radio` | `bool?` | detected | Wi-Fi radio on at first boot; off on a desktop wired to the network, so only the link in use is up. Later toggles (toggle-wifi) persist in NetworkManager's own state; null detects it |
| `base/networkmanager.home_gateways` | `list<string>` | `[]` | Router MACs that make a network home, beside the admin's configs/secrets/keys/home-gateways |
| `base/networkmanager.homelab_dns` | `string?` | unset | The homelab's split-horizon resolver, asked for homelab_domain out a home link (homelab machines) |
| `base/networkmanager.homelab_domain` | `string?` | unset | The homelab's DNS zone |
| `base/networkmanager.homelab_subnets` | `list<string>` | `[]` | The homelab's subnets, routed straight out a home link and through wg0 elsewhere |
| `base/oomd.session_memory_low` | `filesize?` | detected | session.slice's MemoryLow, the desktop working set a build's reclaim keeps; null: 15% of RAM, 2 GiB max |
| `base/pam.fido_origin` | `string?` | detected | FIDO2 origin and appid every enrolled key's mapping was made for (pamu2fcfg -o); null: pam://<hostname> |
| `base/ssh.homelab_hosts` | `list<string>` | `[]` | ssh patterns of the homelab's guests, router and hypervisor: root, accept-new host keys from known_hosts.homelab (homelab profiles only) |
| `base/ssh.wake_router` | `string?` | unset | The always-on homelab router whose `wol-pc` wakes the desktop (wake-pc, homelab profiles only) |
| `base/ssh.wake_host` | `string?` | unset | The desktop wake-pc wakes and then ssh-es into |
| `base/tlp.charge_start` | `int` | `95` | Battery charge level below which charging starts (laptops whose firmware supports thresholds) |
| `base/tlp.charge_stop` | `int` | `100` | Battery charge level at which charging stops; 80 spares an always-plugged battery |
| `base/v4l2loopback.video_nr` | `int?` | detected | /dev/video<n> of the OBS virtual camera; null: a loaded one's, else the first free from 10, past webcams |
| `core/btop.accent` | `string` | `"c4"` | Palette slot for titles, highlights and the selection |
| `core/locale.lang` | `string?` | detected | LANG in /etc/locale.conf; detected: the one bootstrap set |
| `core/locale.formats` | `string?` | detected | Locale for dates, numbers, money, units, paper and addresses (every LC_ but messages and collation); detected: the LC_TIME bootstrap set, unset follows the language |
| `core/locale.keyboard_layout` | `string?` | detected | xkb layout of the console, X11 and the compositor; detected: the one bootstrap set |
| `core/locale.keyboard_variant` | `string?` | unset | xkb variant, e.g. nodeadkeys |
| `core/locale.keyboard_options` | `list<string>?` | unset | xkb options, e.g. ctrl:nocaps |
| `core/locale.wifi_country` | `string?` | detected | Wi-Fi regulatory domain (ISO 3166 alpha-2); detected: the country of the timezone, else the world domain |
| `creating/obs.vaapi_render_node` | `string?` | unset | The /dev/dri render node the vaapi encoders use, by-path so it survives reboots |
| `creating/obs.canvas` | `string?` | unset | Base and output canvas of every profile and the repo collections (Bare, VirtualCam), WxH |
| `creating/obs.mic` | `string?` | unset | The pipewire source node the repo collections' Mic/Aux captures |
| `creating/obs.webcam` | `string?` | unset | The v4l2 device the VirtualCam collection's Webcam captures, by-id so it survives replugging |
| `creating/obs.monitor_device` | `string?` | unset | The pipewire sink node obs monitors audio on |
| `creating/obs.record_encoder` | `string?` | unset | The recording encoder of the Recording and Streaming profiles |
| `creating/obs.stream_encoder` | `string?` | unset | The streaming encoder; h264 is what every ingest takes |
| `desktop/hyprland.monitors` | `list<record>?` | detected | One hl.monitor per output: output, mode, position, scale; detected from the connected outputs, any other output gets its preferred mode and an auto scale |
| `desktop/hyprland.main_monitor` | `string?` | detected | The output holding workspace 1, the bar's notifications, steam's toasts and the tablet; detected: the internal panel, else the largest, leftmost on a tie |
| `desktop/hyprland.workspaces` | `record?` | detected | Workspace to output; detected: the first ceil(10 / outputs) on the main monitor, the rest split over the others left to right |
| `desktop/hyprland.xwayland_scale` | `int?` | detected | GDK_SCALE and QT_AUTO_SCREEN_SCALE_FACTOR for X11 apps (force_zero_scaling); detected: the main monitor's scale rounded, else 1 on a laptop and 2 elsewhere |
| `desktop/hyprland.app_workspaces` | `list<record>` | `[]` | Homes for apps by window class: {class, workspace, silent}; silent opens them without focus |
| `desktop/hyprland.kb_layout` | `string?` | detected | xkb layout; detected from the keymap localectl set (/etc/X11/xorg.conf.d/00-keyboard.conf) |
| `desktop/hyprland.kb_variant` | `string?` | detected | xkb variant; detected like the layout |
| `desktop/hyprland.kb_options` | `string?` | detected | xkb options, comma separated (ctrl:nocaps); detected like the layout |
| `desktop/hyprland.pointer_sensitivity` | `float` | `0.0` | libinput pointer acceleration, -1 to 1 |
| `desktop/hyprland.natural_scroll` | `bool` | `false` | Touchpad content follows the fingers |
| `desktop/hyprland.idle_dim_s` | `int` | `900` | Idle seconds until the screens dim |
| `desktop/hyprland.idle_lock_s` | `int` | `1200` | Idle seconds until the session locks |
| `desktop/hyprland.idle_dpms_s` | `int` | `2100` | Idle seconds until the screens go off |
| `desktop/hyprland.idle_suspend_s` | `int` | `2400` | Idle seconds until suspend, unless an agent works or an inhibitor holds |
| `desktop/hyprland.idle_dim_saver_s` | `int` | `300` | Idle seconds until the screens dim in power saver (a laptop on battery) |
| `desktop/hyprland.idle_lock_saver_s` | `int` | `600` | Idle seconds until the session locks in power saver |
| `desktop/hyprland.idle_suspend_saver_s` | `int` | `1800` | Idle seconds until suspend in power saver |
| `desktop/pipewire.app_loopbacks` | `bool` | `true` | Every app plays through a loopback of its own that carries its system volume, so a capture of the app (obs) stays at full level |
| `desktop/pipewire.eq_target` | `string?` | unset | node.name of the headset sink the eq attaches to as a smart filter; unset, no eq chain |
| `desktop/pipewire.eq_preset` | `string` | `"pro-x-2.txt"` | AutoEq ParametricEQ preset for that headset, a file in this module or an absolute path |
| `desktop/plasma.kwin_outputs` | `bool?` | detected | Ship the committed kwin output layout; detected: on when a connected monitor's EDID is one it describes |
| `desktop/quickshell.pomodoro_focus_min` | `int` | `25` | Minutes of one focus block |
| `desktop/quickshell.pomodoro_break_min` | `int` | `5` | Minutes of the short break after a focus block |
| `desktop/quickshell.pomodoro_long_break_min` | `int` | `15` | Minutes of the long break after the last focus block of a round |
| `desktop/quickshell.pomodoro_cycles` | `int` | `4` | Focus blocks before a long break |
| `desktop/qutebrowser.search_url` | `string` | `"https://duckduckgo.com/?q={}"` | The default search engine, {} is the query; the homelab's searxng is reachable only on a homelab machine |
| `gaming/d2launcher.base_dir` | `string?` | detected | A Diablo II: Lord of Destruction install the game dir is seeded from; detected in the lutris prefixes |
| `gaming/d2launcher.resolution` | `string?` | detected | The monitor the render size derives from, WxH; detected from the focused monitor |
| `gaming/d2launcher.render_size` | `string?` | unset | The 4:3 size the game renders at inside gamescope, WxH; the monitor's full height by default |
| `gaming/gamemode.gpu_device` | `int?` | unset | The /dev/dri/cardN gamemode tunes while a game runs; none leaves the gpu alone |
| `gaming/gamemode.amd_performance_level` | `string?` | unset | The amdgpu power_dpm_force_performance_level during a game; high holds the clocks up, wasteful on battery |
| `gaming/lutris.dpi` | `int?` | unset | Logical dpi wine apps draw at under xwayland (LogPixels), 96 times the main monitor's scale |
| `llm/vllm.model` | `string` | `"RogerS-01/Josiefied-Qwen3-8B-abliterated-v1-AWQ"` | The hugging face repo vllm serves; an uncensored 4-bit AWQ build of Josiefied-Qwen3-8B-abliterated-v1 |
| `llm/vllm.model_revision` | `string` | `"0244c2514cc272a603368c0440ff3002143b2336"` | The model repo's commit, weights and tokenizer alike; bump from https://huggingface.co/api/models/<model>/revision/main |
| `llm/vllm.tool_call_parser` | `string` | `"hermes"` | vllm's tool call parser for the model's chat format (hermes for qwen3, gemma4 for gemma 4) |
| `llm/vllm.reasoning_parser` | `string` | `"qwen3"` | vllm's reasoning parser, which moves the model's thinking out of the reply into reasoning_content |
| `llm/vllm.gpu_memory_utilization` | `float?` | unset | The share of vram vllm takes; the rest stays for the desktop rendering on the same card |
| `programming/android.avd` | `string` | `"nya35"` | Name of the emulator image made from the system image; empty makes none |
| `programming/claude.model` | `string` | `"claude-opus-5-5"` | The model every session starts on |
| `programming/claude.effort` | `string` | `"medium"` | Reasoning effort of that model |
| `programming/task.sync_url` | `string?` | unset | The taskchampion server every replica syncs with as the one client of configs/secrets/keys/taskwarrior-*; none: no sync |
| `programming/task.recurrence` | `bool` | `true` | This replica creates the instances of recurring tasks; one per sync, or each adds its own copy (task-sync(5)) |
| `programming/trmnl-claude.poster` | `bool` | `false` | This machine posts its Claude usage to the TRMNL panel; one poster per panel, a second would overwrite it |
