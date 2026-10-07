# Overhaul

Plan and state of the 2026-10 overhaul. Detailed audit results, the phase 2+3 design draft and the Quickshell
brief stay local in `~/.local/share/dotfiles-overhaul/` (they describe open weaknesses, not for a public repo).

## Phases

1. Scope fixes: every feature affects only what it is meant to affect. **Done** (two fix rounds, about 250 findings,
   uncommitted until the next sync, not VM-tested).
2. Multi-user: a root system layer run once per machine from a root-owned copy, a sudo-free user layer per user,
   per-user profiles replacing the `luca` username check, per-user ledger, `adduser-dotfiles <name>`. Packages stay
   one global set per machine. Machines x users stay additive: machine facts only in `platforms/`, user facts only in
   the profile, never a (machine, user) branch. **Designed, not started.**
3. Simplicity: net lines down, shared helpers only for patterns with 3+ call sites, dead code out. Runs with phase 2.
4. Quickshell redesign and theming coherence. **Brief written, not started.**
5. Domains: coding, pentesting, gaming, socials configured and verified.

Every phase ends with a `test.py` VM run (as luca and as a guest) and a `sync.sh` generation.

## Decisions

- Media playing and an ssh session block suspend only, never idle: dim and lock still happen.
- Coding agents (Claude Code, Hermes) keep the machine awake only while a turn or subagent runs:
  `configs/desktop/idle-guards/agent-guard.sh`.
- Anonymity fails closed. Anonymous SOCKS touches only tor's own traffic (cgroup-scoped persona), no `idspoof`.
- Plasma is a basic but complete backup desktop: security, power, theming; widgets and shaders stay Hyprland-only.
- GPG: armor always, Luca Sandrock is the default key; `gpg-clip` for clipboard decrypt, encrypt and sign.
- Wallpapers: public files are the free or low-res versions; `secrets/wallpapers/` holds only the purchased Alena
  Aenami 4K packs and shadows the public file of the same name. The picker shows only wallpapers that fill the
  screen without visible upscaling and lose at most 10% to cropping (`scripts/wallpaper-list.py`). Themes use
  Aenami wallpapers.
- Quickshell signature ideas: drawers out of the bar's accent line, cold boot (one-shot materialize, glitch only on
  lock and wallpaper change), ASCII projection on the lock screen, palette-sync wipe with a typed log. No hairline.
  Plasma keeps the modernclock widget. noice.nvim is replaced by nvim ui2 plus the snacks notifier.
- Album art: remote covers only on the home network, otherwise local art only.
- Printing: the system layer creates the PDF queue and a permanent driverless queue for every IPP Everywhere /
  AirPrint printer found over mDNS, bound to its `.local` name, at config time and again on every home connect.
  Guests answer once in the bootstrap TUI whether the current network is their home.
- Claude Code defaults to Opus 5.5 at medium effort.

## Pending owner steps

- Print `~/age-recovery-key.txt` (paper recovery recipient, already sealed into `secrets.key.age`), then shred it.
- `sync.sh`, then a mirror build (brings the `theharvester-git` dependency fix).
- `./test.py run` before running `config.sh` on a real machine: the boot chain moved to signed UKIs.
- Homelab: a Samba user `luca` with the password in `secrets/samba-homelab` and an encrypted, signed `homelab`
  share; the NAS automount stays off until it exists.

## Next session

1. Phase 2+3 from the saved design, foundation group first.
2. Quickshell redesign with the four signature ideas, the brief's bug and idle-cost fixes, tokens, shared chrome,
   translucency via Hyprland layer rules.
3. Printing as decided above, plus `ipp-usb`, `sane-airscan` and Portmaster rules for avahi and cupsd on the LAN.
4. Wallpaper resolver wiring: `switch-wallpaper.sh list/set/random` and the Quickshell picker through
   `wallpaper-list.py`, theme `wallpaper` fields as bare names, lock screen decoded at physical resolution.
5. VM test as luca and as a guest.
