# Known bugs

Open findings from the full AI code review of 2026-10-15. The 52 bugs that were fixed in that pass are not listed
here; this file is the backlog of what was found and deliberately left alone, so it is not rediscovered every time.

Confidence is the reviewer's, 1-10. Nothing here is dangerous today by the standard in `AGENTS.md`: no auth bypass,
no data loss, no broken boot or desktop. Most are latent, cosmetic, or a deliberate tradeoff.

## Correctness, narrow error paths

- `configs/gaming/dalamud/mod.nu:52` - `ls $dir | where type == dir | last` is null for a plugin directory with no
  version subdirectory, left by an uninstall or an interrupted `plugin-restore.nu`. The following `path join` then
  raises and aborts the whole `backup` verb, so no dalamud state is saved at all. Guard with `if $newest == null`.
  (6)
- `configs/pentesting/caido/mod.nu:54` - `^pgrep -f caido-cli` exits 1 when nothing matches and a non-zero external
  aborts the pipeline. That is exactly the failure path, so the script dies with a generic "External command failed"
  instead of reaching `job kill` and its own diagnostic; the spawned job and temp log leak. Wrap in `complete`. (6)
- `configs/gaming/vpn-bypass/mod.nu:26` - the `nudge` step runs `nmcli` guarded only by the existence of
  `/etc/NetworkManager/dispatcher.d`. On a fresh install where NM is installed but not yet running, `nmcli` exits 8
  and the step errors, recording the system apply as failed even though every file was written correctly. (5)
- `configs/programming/nvim/mod.nu:24` - `head-commit` falls through to reading `packed-refs` with no existence
  check when HEAD is a symref and the loose ref is missing. `open --raw` on a missing file aborts the whole `link`
  verb instead of marking one plugin stale. 87 of 113 installed lazy plugins take the symref path, so one partial
  clone breaks `dot link programming/nvim` entirely. (5)
- `weblinks/mod.nu:9` - `parse-links` strips blank lines but not `#` comments, unlike every other list file in the
  repo. A comment line makes `$url` = `#` and aborts the whole `link` verb, so no weblink command is written.
  `links.txt` has no comment today, so this is latent. (5)

## Converge and lifecycle

- `configs/programming/vscode/mod.nu:30` - the palette-rendered `settings.json` uses plain `file-text`, not
  `--generated`. Only `--generated` files are rewritten unconditionally (`scripts/lib/converge.nu:114`); otherwise a
  hash mismatch is drift and is skipped. VSCodium rewrites that file on any settings-UI change, so after the first
  such write `dot theme apply` silently stops recolouring it and `telemetry.telemetryLevel` stops being enforced.
  Wants `--generated`, or `json-merge` since the current code also discards VSCodium's own keys. (6)
- `skills/mod.nu:20` - `link` registers the checkout with `gemini skills link`, but the module has no `unlink` verb
  and the engine can only undo recorded `file`/`link` outputs, not a `step`. `dot unlink skills` removes the
  `~/.claude|.copilot|.hermes/skills` symlinks and leaves gemini registered. (6)
- `configs/desktop/gtk` races `configs/desktop/oomox`: gtk names the theme `oomox-colors-oomox` that oomox
  generates, with no dependency between them.

## Deliberate tradeoffs, confirm before changing

- `configs/base/systemd/mod.nu:37` masks `NetworkManager-wait-online.service`, which makes `network-online.target`
  fire immediately. Six units order themselves after that target and now start before the network is up. Removing
  the mask costs boot time on every machine; the blast radius is why it was left.
- `configs/base/hardening/sysctl-hardening.conf:18` sets `fs.suid_dumpable = 0` while the coredump module expects
  dumps. This reads as intentional hardening rather than a mistake.
- Firewall narrowing in `configs/base/nftables`: the tunnel fwmark rule accepts both protocols where only UDP is
  needed, and the inbound chain does not enumerate MLD types. Both are judgement calls about how tight to go.
- `configs/base/yubikey/mod.nu:23` installs an `id_ed25519_sk` stub from only the first matching key, so a second
  resident key is never wired up.

## Cosmetic and low impact

- `configs/base/xdg/app-dirs.conf:22` - `MINIKUBE_HOME` points one level above where minikube expects it.
- `configs/base/fancontrol/mod.nu:12` enables `lm_sensors.service`, which is a no-op oneshot on current Arch.
- `configs/base/ossec/ossec-journal.service:14` appends to `/run/ossec-journal.log` with no size bound, on tmpfs.
- Two theme palettes give `accent2` and `urgent` the same colour, so urgency is invisible on those light themes.
- `{wallpaper}` in the wallust templates holds the colorscheme path, not the image path.
- Several user units hardcode `%h/projects/arch-dotfiles` instead of deriving the checkout.
- `configs/base/tablet/tablet-driver.py` and `verify-mapping.py` each had a defect reported; they were not recorded
  in detail and need a re-read before anyone acts on them.

A further set of low-severity quickshell/QML findings (mostly unlikely races that heal themselves on the next
event, and binding nits) was reviewed in the same pass and dropped without individual records.
