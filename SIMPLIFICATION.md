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

Now: `scripts/toggles/toggle-font.nu` (251) rewrites tracked repo files (ghostty `config`, kitty `kitty.conf`,
qutebrowser `config.py` and `startpage.html`, zed `settings.json`, emacs `early-init.el`, discord `wal.theme.css`,
spotify `user.css`, quickshell `theme.json`). To make that visible live, those modules `file-link` the repo file
instead of copying it (comments like "a link: toggle-font rewrites the repo file" in `desktop/kitty/mod.nu`), and
`scripts/lib/wallpaper.nu` calls the toggle when a theme names a font. Every font switch dirties `git status` and
lands in the next `Generation` commit.

Proposed: the font is a field of the theme state, next to the palette (`~/.cache/wal/` already carries the
palette). `dot internal theme apply` writes `font.json` beside it; each module renders its font in its `theme` verb
from that file with `file-text --generated`, the way colors work. `toggle-font.nu` shrinks to a cycle over a font
list that sets the field and runs the theme apply.

Removes: about 200 lines of `toggle-font.nu`, the per-app regex edits, 8 of the 20 `file-link` exceptions (they go
back to managed copies), the dirty checkout.

Risk: medium. Apps that only read their font at start need their existing reload hooks; emacs reads
`early-init.el` once.

Migration: add the font field and the per-module renders, switch each module from `file-link` to `file-copy`
plus a generated font include, reset the font lines in the repo files to the default, delete the regex edits.

Verify: `dot theme <name>` with a font on a dark and a light theme (skill `l-dotfiles-theming`), `git status`
clean afterwards, `dot test lint`.

## 2. One serialized theme run

Now: a theme switch starts from the bar, `toggle-theme-mode.nu` (99), `dot theme` or the wallpaper picker; each runs
`scripts/lib/wallpaper.nu` (101) in the caller's process with a `theme.lock`, a background and a foreground pass of
`dot internal theme apply`. Switching fast queues several full runs or interleaves them; a module whose theme verb
fails or is skipped keeps the previous palette (the reported dolphin search bar and nvim lualine bleed).

Proposed: every caller writes the wanted wallpaper or theme into one request file and starts
`dot-theme.service` (user, `Type=oneshot`). systemd never runs it twice at once; the unit reads the latest request
when it starts, so ten fast clicks cost at most two runs and the last one wins. Every theme verb gets the palette by
path and a run id, and records it, so `dot status` can name a module still on an older palette.

Removes: the lock and its stale handling, the duplicated launch code in the toggles and the picker, the
background/foreground split if the unit's ordering covers it. About 80 lines; fixes the class of bug instead of
each symptom.

Risk: low. Native mechanism (systemd's own job queue).

Verify: switch themes ten times in two seconds, then `dot status` shows every themed module on the final palette.

## 3. Homelab coupling by hostname only

See the homelab section below; listed here for order. Removes the duplicated homelab blocks in two platform option
files and every literal address of a guest.

## 4. A fixed verb set, one-off verbs become plain scripts

Now: `mod.nu` files export 153 `link`, 70 `system`, 25 `theme`, 14 `detect`, 9 `backup`, 6 `seed` and 84 other
names used by one to three modules (`wine-dpi`, `wine-bin-fixup`, `wifi-teardown`, `mcp-cache`, `tunnel`,
`theme-push`, `relocate`, `profile-create`, `xcu-update`, `wire`, ...). They are reached from units, toggles and
`dot internal`, each with its own call shape.

Proposed: the engine knows `link`, `system`, `theme`, `detect`, `backup`, `restore`, `update` and nothing else. A
module's helper that a unit or toggle runs is a script file in the module dir (`files-into` or `link-commands`
already install them), called by path. `seed` folds into `restore` (both put state back), `relocate` into a
migration.

Removes: the verb dispatch for arbitrary names in `modules.nu` and `internal.nu`, the per-name calls; makes a verb a
contract the lint can check. About 150 to 250 lines.

Risk: medium, many small edits. Each removed verb has its callers in units and toggles; `grep` finds them.

Verify: `dot plan --modules`, `dot test lint` with a new check that only the fixed verbs are exported.

## 5. `update` verb, `system-update.nu` and the non-owner update path

Now: `scripts/system-update.nu` (49) knows every tool's upgrade (flatpak, rustup, opam, ghcup, hyprpm, tldr, nvim
lazy and mason, emacs packages) and runs `dot apply --packages` and `dot apply` itself. A machine without the signing
key updates with `dot sync`, which stops after the apply, so this path and `system-update` overlap.

Proposed: each module owns its upgrade in an `update` verb (nvim's mason and lazy in `programming/nvim`, ghcup in
`programming/ghcup`, ...). `dot sync` is the one update command for everyone: pull, migrate, install, apply, every
`update` verb, then backup, commit and push only where the machine signs. `system-update.nu` is deleted.

Removes: `system-update.nu`, the hardcoded tool list; answers "how does a non-owner update" with the same command
the owner runs.

Risk: low.

Verify: `dot sync --no-push` on a machine without the key in the VM test.

## 6. One state store

Now: dot's state is spread over `written` (hash per written file, `written.nu` 120), `seen`, `ledger` (enabled units,
installed packages, package snapshots per generation, `ledger.nu` 90), `modules/<id>/<verb>.nuon` (input hash and
outputs per verb, `converge.nu`), the drift reports (`drift.nu` 141) and `preserved/`. Drift, `explain`, `module
remove` and the doctor each join several of them.

Proposed: the per-verb record is the only record: outputs with their hash, mode, units enabled, packages declared.
`written` and the unit and package halves of the ledger become queries over all records; the ledger keeps only the
per-generation package snapshot that `rollback --full` needs.

Removes: about 150 lines and the class of bugs where two stores disagree.

Risk: high. State migration on every machine; needs a migration with a real `down`.

Verify: before and after the migration, `dot plan`, `dot status --json` and `dot explain` on a sample of paths give
identical answers.

## 7. Engine lib holds only the engine

Now: `scripts/lib` carries feature code: `anonymous-socks.nu` (195, the tor SOCKS pool), `yubikey.nu` (274),
`wallpaper.nu`, `wallpaper-list.nu`, `wallpaper-pick.nu` (225 together), `picker.nu`, `audit.nu` (156).

Proposed: each moves into its module dir (`base/tor`, `base/yubikey` or the secrets module, `core/wallust`,
`core/gnupg`), loaded by the CLI from there. `scripts/lib` shrinks to plan, apply, state, CLI, install and test.

Removes: no lines by itself; makes the engine size the engine's and makes each feature removable with its module.

Risk: low; `use` paths change.

Verify: `dot test lint`, `dot --help`, each moved command once.

## 8. Toggle protocol as data

Now: a toggle prints a label line, and `scripts/toggles/status.nu` parses it: `●`/`○` prefixes, ` (on)`/` (off)`
suffixes decide `on`, `setting` and `cycles`. The settings window's `Schema.js` (251) and the bar re-derive the
same. Root halves go through `root-run` per call, so a toggle that touches several root things prompts several times
(the firewall toggle asks for the password about four times).

Proposed: `toggle-<name>.nu get --json` answers `{name, label, state, states, available}`; `status.nu` concatenates.
A toggle's root half is one `system-apply.nu toggle <name> <state>` call, so one prompt per flip.

Removes: the label parser, glyph conventions in every toggle, about 60 lines, and the repeated prompts.

Risk: low.

Verify: `scripts/toggles/status.nu | from json`, flip every toggle from the bar.

## 9. Values defined once

Now: the background value clamps live in `configs/core/wallust/palette.nu`, `Commons/Theme.qml` and
`quickshell/theme.json`; `lint-palette` in `gate.nu` compares the three. `Palette.js` is generated from `palette.nu`
and checked by `dot internal gen --check`. `scripts/lib/system-apply.nu` re-execs each command under flock with its
flags spelled out again, and `lint-locked-flags` checks that none is dropped.

Proposed: `dot internal gen` also writes the clamps into a generated qml/json fragment; `lint-palette` goes.
`locked` re-execs with the original argv verbatim, so `lint-locked-flags` goes.

Removes: two lint checks (about 40 lines) and two places a value can drift.

Risk: low.

Verify: `dot internal gen --check`, `dot test lint`.

## 10. Quickshell: shared parts and events instead of polling

Now: 28k lines. `Ui/` has eleven button, toggle and card components (`Button`, `ActionButton`, `BarIconButton`,
`PanelActionButton`, `WidgetButton`, `Toggle`, `ToggleSwitch`, `Chip`, `PopupCard`, `OverlayCard`, `HoverPanel`,
1223 lines together). 82 raw `Process {}` blocks beside the `JsonProcess`, `KeyValueProcess` and `ProcessQueue`
helpers. Polling timers: `Network.qml` every 2 s, `Media.qml` every 1 s, `Notifications.qml` 30 s, `Homelab.qml` runs
`homelab-status.nu` every 30 or 300 s, `Weather.qml` a 250 ms timer. Large single files: `Weather.qml` 1083 (its own
chart, the misaligned rain and temperature diagram), `System.qml` 986, `ImagePicker.qml` 956, `Service.qml` 883.

Proposed:
- `Ui/Button` with a variant, `Ui/Toggle`, `Ui/Card`: three components replace eleven.
- Every script call through `JsonProcess`; raw `Process` only for streams.
- Event sources where the system has them: NetworkManager's D-Bus signals (`nmcli monitor` at most) for Network,
  MPRIS `positionChanged` plus a local clock for Media, the notification server's own signals, a ntfy or SSE push
  for the homelab status instead of a poll.
- One `Ui/Chart` (axes, bands, labels on one layout grid) used by Weather, `Sparkline`, `Heatmap` and `BarGauge`;
  fixes the diagram alignment once.

Removes: an estimated 3000 to 5000 lines; idle CPU from the polls.

Risk: medium, visual. Each widget lands alone with screenshots (skill `l-dotfiles-quickshell-dev`).

Verify: screenshots before and after per widget on a dark and a light theme; `qmllint` through `dot test check`.

## 11. Pick one of each (needs a decision)

The repo configures several tools for one job. Each kept one costs its module, its theme verb, its font edit and its
apparmor profile where it has one. These are questions, not findings:

- Editors: `programming/nvim` (246), `programming/emacs` (2193, a full doom-style config), `zed`, `vscode`,
  `jetbrains`.
- Terminals: `desktop/ghostty`, `desktop/kitty`, `desktop/konsole`.
- Browsers: `desktop/firefox` (513), `desktop/chromium`, `desktop/qutebrowser` (555).
- Shells: `core/zsh` (`zshrc` 172) and `core/nushell` (`config.nu` 159) duplicate aliases (`sshpc`, `sshnb`, ...). If
  both stay, one alias table rendered into both.
- VPN paths: `base/protonvpn` (the app), `base/protonvpn-netns` (164, fail-closed netns), `gaming/vpn-bypass` (145),
  `base/wireguard`, `base/tor` plus the SOCKS pool. Each is a real feature; the toggles around them
  (`toggle-protonvpn`, `toggle-vpn`, `toggle-anonymous-socks`, `toggle-tor`, `toggle-offline`) could be one n-state
  `toggle-route` (direct, homelab, proton, tor, offline) if they are mutually exclusive in practice.
- Firewalls: `base/nftables` (190) and `base/portmaster` (116) both filter; `portmaster-bypass.nft` exists to make
  them coexist. One filter, the other dropped or reduced to its UI.
- `desktop/plasma` (1536): kept for dolphin, kded and KDE apps; if only the apps are wanted, the applet layout and rc
  templates can go.

## 12. Assets out of git

Now: `wallpapers/` 121 MB, `showcase/` 13 MB, `desktop/shimoji` 8.3 MB of `.wlshm` packs in the public repo. Every
other user clones them.

Proposed: pinned `fetch-file` downloads (the mirror can serve them) or `configs/secrets/state` for the bought ones;
`showcase/` on the mirror or the README host.

Removes: about 140 MB from every clone and the ISO's verified checkout.

Risk: low; needs a history rewrite only if the clone size matters, otherwise only future clones of a fresh mirror
benefit.

## 13. Install and VM test

Now: `bootstrap.sh` (46), `scripts/lib/bootstrap.nu` (894), `bootstrap/questions.nuon` (322), `iso-install.nu`
(222), `iso.nu` (122), `stage.nu` (134); the VM test `vm.nu` (569) plus `vm/` (200) drives the Arch iso by sendkey
and OCR.

Proposed: the lsck0 iso with an answer file is the one unattended path (`lsck0.*` boot parameters already map to
`BOOTSTRAP_*`). The VM test boots that iso with an answer file and only watches beacons, so the sendkey and OCR
driver goes. `curl | sh` stays for WSL and foreign live systems, sharing `questions.nuon`.

Removes: about 300 lines of VM driving.

Risk: medium; the Arch-iso route loses its end-to-end test.

## 14. Rarely used engine features (needs a decision)

- `dot plan --sandbox` (`sandbox.nu` 146, `plan-systemctl.nu` 106): a bubblewrap apply to show the write set. `dot
  plan` already lists actions per module.
- `dot rollback --full` (`rollback.nu` 208): reinstalls packages from a mirror snapshot and a nixpkgs pin. Plain
  `rollback` (check out and converge) is a fraction of it.
- `dot test drill egress`.

Each removed one takes its tests, docs and completion entries with it. Keep what is used.

## 15. Docs from the source

Now: `FEATURES.md` (638), `README.md`, root `AGENTS.md` (165), 18 group or module `AGENTS.md`, 13
`l-dotfiles-*` skills, 506 lines of module READMEs. The feature list and the module list drift from the modules.

Proposed: `meta.doc`, one line per module; `dot explain --modules` (or a generated `FEATURES.md` checked by
`dot internal gen --check`) replaces the hand list. Skills keep procedures only, no lists that the code already
answers.

Removes: about 500 lines of hand-kept lists.

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
estimate is 4500 to 7000 lines removed (most of it quickshell), 140 MB of assets out of the clone, two lint checks
and one state store fewer. Each decision in 11 removes a whole module tree on top (emacs alone 2193 lines).
