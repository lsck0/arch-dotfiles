# Simplification

Proposals to remove technical debt and leftover experiments while every feature stays. Nothing here is done yet;
each item is one change, landed and verified on its own, in the order given. Line counts are from 2026-10-25
(`wc -l`); removal estimates are rough.

Baseline: 62k lines of nu, qml, js, lua, sh and py tracked outside `configs/secrets`, of which quickshell is 28k,
the engine (`scripts/dot.nu` plus `scripts/lib`) 8k, the 213 `mod.nu` with their files the rest.

## Principles the proposals apply

- The engine is the engine: `scripts/lib` holds plan, apply, state, CLI and install. A feature of one module lives in
  that module's dir.
- One protocol per kind of thing: verbs have a fixed set, toggles answer one structured record, the bar reads one
  JSON shape, the repo is never rewritten at runtime.
- A value is defined once and generated everywhere else; a lint that compares copies of a value is a sign the value
  is defined twice.
- The homelab is reached by name, never by address.

## 1. Font becomes a theme input, the repo is never rewritten at runtime

Done: the font lives in `~/.cache/wal/font.json` beside the palette (`configs/core/wallust/font.nu`: `font-load`,
`font-save`, the defaults and the monospace partners). `toggle-font.nu` (251 to 94 lines) saves it and requests a
theme run through `dot-theme.service`; a theme's `"font"` is saved the same way. Each program gets it from its own
theme verb: a generated include (ghostty, kitty, emacs, firefox chrome), a rendered config (zathura, gtk.css, the
qutebrowser start page, zed settings), a merge (vscodium, kdeglobals, discord and spotify css), or a read at start
(qutebrowser `config.py`, nvim's guifont, quickshell's `Theme.qml` watching the file). Seven repo `file-link`s became
managed copies; a font switch leaves `git status` untouched. Neovide now follows the terminal size (was a fixed h16).

## 2. One serialized theme run

Done: every caller writes `$XDG_RUNTIME_DIR/theme.request` and starts the user unit `dot-theme.service`
(`dot internal theme serve`, `configs/core/wallust/dot-theme.service`), whose loop applies the newest request until
none newer is left; the token, `theme.lock`, `theme-background.lock` and the foreground/background split are gone
(`THEME_ORDERED` only orders spotify before discord). Ten switches in two seconds: one unit run, ends on the last.
Not done: a per-module palette id for `dot status`.

## 3. Homelab coupling by hostname only

See the homelab section below; listed here for order. Removes the duplicated homelab blocks in two platform option
files and every literal address of a guest.

## 4. A fixed verb set

Done: the count above was a miscount; the other 84 names were never dispatched by name, they are `step` targets of
their own mod.nu (`seed`, `relocate`, `setcap`, ... run by the engine's `step` declaration) or helpers another module
imports (`lod-detect`, `spicetify-colors`). `VERBS` dropped the two nobody exported (`unlink`, `check`) and the
`unlink` call in `dot module unlink`; `HOOKS` is exported beside it, and `lint-exports` (`gate.nu`) fails any
`export def` that is no verb, hook, step of its file or import of another module. `seed` stays a first-apply step, not
a `restore`: it runs once when the live file is missing, `restore` on demand.

## 5. `update` verb, `system-update.nu` and the non-owner update path

Done: `update` is a verb (`base/essentials` rustup, `programming/opam`, `desktop/hyprland` plugins,
`programming/nvim`, `programming/emacs`), `dot sync` runs them after the apply through `dot internal update`;
`system-update.nu` is gone. Flatpak commits and ghcup versions are pins and move by a repo edit; tldr keeps its
weekly timer, which works for a machine that rarely syncs.

## 6. One state store

Done: `modules/<id>/<verb>.nuon` is the one record of what dot wrote. Each file output carries the time dot wrote it
(`at`, ns) and an owned json/ini merge is an entry of its own; `recorded-hashes` is the newest write per path over
all records, so `written`, its `seen` list, `written-record`/`written-forget`/`written-prune` and their locked.nu
halves are gone (`written.nu` is now `preserve.nu`: the preserved/ dir, the ~/sync guard, tty-confirm). The
wireguard config is a declaration instead of a step writing behind the engine. The per-generation `generations`
file went with `rollback --full`. Migrations `0001` (user) and `0002` (system, also run by `dot apply --system`)
fold the old files into the records and keep them under `migrated/0001` for `down`. The ledger keeps units,
packages, migrations and the lsck0 snapshot: dot owns a unit its modules' files name and a package a meta declares,
neither a verb's output, and the snapshot feeds the doctor's mirror-age check and the drift report.

## 7. Engine lib holds only the engine

Done: `anonymous-socks.nu` in `base/tor`, `yubikey.nu` and `audit.nu` in `base/yubikey`, `wallpaper*.nu` in
`core/wallust`, `picker.nu` in `desktop/hyprland`; `scripts/lib` keeps the engine.

## 8. Toggle protocol as data

Done: every toggle answers `get --json` with one status record from `status-record` in `scripts/toggles/lib.nu`
(`{name, label, state, text, states, on, available}`; `available` folds the old `available` verbs and the network
panel's own nmcli probe); `label`, the `●`/`○` and ` (on)`/` (off)` conventions and `status.nu`'s parser are gone.
`status.nu [name...]` concatenates the records, the menu, the settings window (`Schema.toggleIsSwitch`) and the network
panel (one `status.nu` call instead of twelve processes) read them. Every flip already makes at most one root call.

## 9. Values defined once

Done: `Theme.qml` takes the clamps and light luminance from `Palette.js`'s generated block (theme.json only
overrides), `lint-palette` and the luminance copy check are gone; `locked` re-execs the command line verbatim,
`lint-locked-flags` is gone.

## 10. Quickshell: shared parts and events instead of polling

Done: `Ui/Button` takes a `variant` (plain, icon, action, chip) and replaces `PanelActionButton`, `ActionButton` and
`Chip`; `Ui/Toggle` is the one on/off switch (`ToggleSwitch` renamed; the row card's only user, the DND row, is a
`PanelRow` like every other toggle row). The JSON-reading script calls (display, network, clock, keyboard, lock notes,
workspace rules) go through `JsonProcess`; raw `Process` stays for streams, stdin writers and plain-text output.
The Doctor indicator's 10-minute reload is gone (its `FileView` watch already reloads).

Kept, on purpose: `WidgetButton`/`BarIconButton` (bar items: bar tooltip, wheel, vertical bar); `PopupCard`,
`OverlayCard`, `HoverPanel` (three different window kinds, not cards of one shape); the remaining timers, which are
clocks or run only while their panel is open (network throughput, media position, notification ages); the Homelab
poll until the lab pushes status; `Sparkline`, `Heatmap`, `BarGauge` as they are, since Weather composes them on one
slot grid already and a shared `Ui/Chart` would add code. The doc's 3000 to 5000 line estimate assumed the polling
and the Weather chart were still bespoke; the rest of the 28k is feature code.

## 11. Pick one of each

Decided: keep all editors, terminals, browsers, both firewalls; one route toggle.

Done (route): `toggle-route.nu` (direct, proton, tor, offline) replaces `toggle-protonvpn`, `toggle-tor` and
`toggle-offline`; the network panel picks a route like the firewall mode, `auto-vpn` and `timezone-auto` read it.
`toggle-vpn` (wg0 carries only the lab subnets) and `toggle-anonymous-socks` (SOCKS ports on lo) are not routes: they
work beside any of them and stay separate; offline still takes wg0 down and restores it.

Still open: the shells' duplicated aliases (one table rendered into both, with item 3); `desktop/plasma` trimmed to the
KDE apps if the applet layout is unused.

## 12. Bought wallpapers move to ~/sync (decided: public assets stay in git)

Done: the 53 bought wallpapers (223 MB) live in `~/sync/wallpapers`, copied and checksum-verified, removed from the
secrets submodule (staged, the next `dot sync` commits it); `wallpaper-list.nu` resolves `~/sync/wallpapers` before
`wallpapers/`, `wallpaper-import` copies into it. `wallpapers/`, `showcase/` and the shimeji packs stay in git.

## 13. Install and VM test

Done: `dot test run` boots the lsck0 iso (the published one, sha256-checked, or `--iso`) with an answer file and
types and reads nothing: the answers' `report` url (`BOOTSTRAP_REPORT`, `questions.nuon`) makes the stub upload its
log and beacon `bootstrap-fail` on failure, each stage beacon `install-*`/`config-*`, and the disarmed chain's end
run `scripts/lib/stage-report.nu` as root from the root copy (invariant probes, backup roundtrip, logs up as
`logs.tgz`, beacon `chain-done`). Gone: the sendkey key tables and typing, the tesseract screen reading, the tty
login, the typed Arch-iso bootstrap, `dot test logs` and `dot test type`; `vm.nu` 455 to 251 lines, `serve.sh`
serves beacons and uploads only. `curl | sh` stays for WSL and foreign live systems. Lost coverage: the Arch-iso
route has no end-to-end test, and the finished system's first boot past the disk passphrase is no longer checked
(the report runs right before that reboot).

## 14. Rarely used engine features

Done: `dot plan --sandbox` (`sandbox.nu`, `plan-systemctl.nu`, the plan notes, `locked.nu units-set`), `dot rollback
--full` (the snapshot, mirror and nixpkgs pin lookups, the `--pin`/`LSCK0_SNAPSHOT` plumbing to root) and `dot
test drill egress` (`vm/egress.nu`, `vm/bypass.nu`, `vm/prelude.nu`, the drill steps in `vm.nu`) are gone.

## 15. Docs from the source

Done: `FEATURES.md`'s Options table is generated by `dot internal gen` from every public module's `options` (type,
default, `detected` when the module's detect hook names it, doc) between two markers, and `gen --check` in
`dot test lint` fails a stale copy; the hand copy had drifted (10 options missing, docs out of date). The quickshell
skill points at `quickshell ipc show` instead of a hand list of IPC targets. No `meta.doc`: the topical prose in
`FEATURES.md` is not a module list, and a one-liner per module would be a new hand-kept list. The AGENTS.md skill
table stays, it is the agents' index.

## 16. Migrations

Already squashed: `migrations/` holds only `0000-sample.nu`. Keep the mechanism; each proposal above that moves state
(6, 1, 4) ships one migration.

## Homelab

The homelab is being restructured (about 31 guests into about 9 VMs: core, security, dev, media, home, selfhost,
edge, minecraft, ts); vmids and possibly addresses change, `tasks.lsck0.dev` and `cal.lsck0.dev` stay. Every
literal address or vmid in this repo breaks with it.

Hardcoded today:

| where | what |
|---|---|
| `platforms/pc.options.nuon`, `platforms/notebook.options.nuon` (duplicated) | `base/networkmanager.homelab_dns` `192.168.178.29`, `homelab_subnets` `10.100.0.0/16`, `10.200.0.0/16`; `base/ghostmirror.homelab_mirror` `http://10.100.0.104:8090/...`; `base/ssh.homelab_hosts` `10.100.0.*`, `10.200.0.*`, `192.168.178.29`, `192.168.178.200`; `wake_router` `192.168.178.29`, `wake_host` `192.168.178.138` |
| `scripts/lib/bootstrap.nu:18-19` | `HOMELAB_MIRROR`, `HOMELAB_MIRROR_PROBE` on `10.100.0.104:8090` |
| `configs/core/nas/mnt-homelab.mount:14` | `What=//10.100.0.104/homelab` |
| `configs/core/syncthing/README.md:3` | `vm-104-nas`, `10.100.0.104` |
| `configs/core/zsh/zshrc:107-108`, `configs/core/nushell/config.nu:111-112` | `sshnb`/`sshpc` by LAN address |
| `configs/base/boot/remote-unlock/README.md:60` | `ssh root@192.168.178.29 wol-pc` |
| `configs/desktop/quickshell/plugins/bar/widgets/homelab-status.nu` | guests keyed by vmid (`route.r.vmid`, `vm-<id>` parsed, `by_ip`), `UNKNOWN_VM_ID`; reads `lab.json` schema 1 |
| `skills/l-dotfiles-live-debug/SKILL.md:71` | the guest subnets in prose |
| `scripts/lib/vm.nu:505-513`, `scripts/lib/vm/bypass.nu` | test fixtures for the egress drill (fake addresses, fine to keep) |

Proposed:

1. One owner-level homelab record in the secrets submodule (where the owner's lab facts belong, not in two platform
   files): resolver, domain, and names only. The one address that cannot be a name is the resolver used before DNS
   works; everything else is `*.lsck0.dev` (the mirror, the NAS share as `//nas.lsck0.dev/homelab`, the wake router).
   `base/networkmanager`, `base/ssh`, `base/ghostmirror`, `core/nas` and `bootstrap.nu` read it; the platforms keep
   only `homelab: true`.
2. Split DNS stays native: NetworkManager routes `~lsck0.dev` to the lab resolver. Subnets for the firewall come from
   the record, not literals.
3. `ssh` matches `Host *.lab.lsck0.dev` instead of address globs; the LAN aliases for the pc and notebook move
   into the ssh config as `Host` entries, out of both shells.
4. `lab.json` schema 2: guests keyed by their stable name, vmid only an attribute; routes reference the guest name.
   `homelab-status.nu` and the ntfy notifier join by name. The bar receives status by push (ntfy or SSE) instead of
   polling every 30 s.

Agreed with the homelab session (`homelab-f2`, grouping confirmed by Luca; its side is in
`~/projects/homelab/SIMPLIFICATION.md`, section Dotfiles):

- Bootstrap keeps one address: the resolver `192.168.178.29` (the lab's `site.json` `lan.router`).
- Names after the merge: `nas.lsck0.dev` (the smb share `//nas.lsck0.dev/homelab` and syncthing),
  `archmirror.lsck0.dev` (replaces `10.100.0.104:8090`), `router.lsck0.dev` (wake on lan), `mirror.lsck0.dev`
  unchanged. Every VM is also `<name>.lab.lsck0.dev`, so ssh matches `Host *.lab.lsck0.dev`.
- Route names (`tasks`, `cal`, `ntfy`, ...) do not change. `10.100.0.104` stays valid until the merge lands.
- The subnets do not change; the dotfiles read them from the zones in `lab.json` instead of literals.
- `lab.json` schema 2 keys guests by stable name (`core`, `security`, `dev`, `media`, `home`, `selfhost`, `edge`,
  `minecraft`, `teamspeak`, `router`, `worker-<n>`) with `vmid` and `ip` as attributes; routes carry a `guest` name
  and no vmid. The schema stays 1 until the lab ships 2, so `homelab-status.nu` switches when `LAB_SCHEMA` does.

## Order and estimate

Low risk first: 2, 7, 8, 9, 5, 3, 1, 4, 10, 15, 12, 13, 6; 11 and 14 wait for a decision. Without 11 and 14 the
estimate is 4500 to 7000 lines removed (most of it quickshell), 223 MB of bought wallpapers out of the secrets submodule, two lint checks
and one state store fewer. Each decision in 11 removes a whole module tree on top (emacs alone 2193 lines).
