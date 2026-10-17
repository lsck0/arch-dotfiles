This system was installed with those dotfiles, do a full and throughrow review of both the dotfiles and the system it created.
Use workflows and address the list of bugs below. Fix absolutely everything and make this perfect.
Especially do a ui/ux pass and make sure that all themes, fonts, transparencies match.
Make sure no userfacing texts look blatantly ai generated, remove ai-isms.
Make sure that both me and other people can use this setup reliably.

Bugs i found:

- zapzap, telegram cant save/upload files
- spotify did not automatically theme when opened
- remove the "mark as read" button on notifications
- nvim error: vim.schedule callback: Keyboard interrupt stack traceback: [C]: in function 'getcompletion' ...hare/nvim/lazy/transparent.nvim/lua/transparent/init.lua:46: in function 'fn' [string "vim/_core/editor"]:526: in function <[string "vim/_core/editor"]:521>
- the music viz in the bar and in the widget are not the same? use the one in the bar but make it better and more
  responsive to the music playing
- tab autocomplete for tags does notwork in mod+o, it changes to notes and changing back the bar is empty..
- clicking on firewall turns restrictive but clickig again doesnt go back or forward... it should be permissive,
  default, restrictive
- in nvim it auto new lines when it gets too long, which is cool, but that does not respect the tab indentation at the front
- bluetooth, wifi, etc start auto enabled, it should only enable either ethernet or wifi, depending whats used in the install
- now that raddebugger had a linux release, also install that.
- widgets sometimes not close when clicking outside
- modtab should show one global list of all workspaces and not just the ones on your monitor
- tmux fingers is not working
- the top bars of firefox and chrome should be a lil bit transparent, glass morphism style
- discord is lagging A LOT when enabling camera, both real and virtual
- ff14 rshift+f12 doesnt bring up mangohud, not working in other steamgames, like deadlock either
- in nvim, seeing the chooses autocomplete option is really hard
- make the timezones like NA west/central/east UK, Central EU, NZ, jp
- spotify is not live changing theme
- in settings, ctrl w or ctrl backspace should delete the word. closing window should clear search
- the Diablo2 / Median XL / PD2 setups are still rather broken
- font size and family changing is not live across everything...
- there are also artifacts from changing themes, ie going from light to dark some things stay white in nvim like lualine
  or treesitter context bars
- take new and better showcase screenshots
- dot cli could have a overhaul, so many slightly different commands. main workflow should be ONE. dot sync: pull,
  apply, push. one command to bring the pc to what the dotfiles prescribe
- leader fp doesnt find sdd and probe
- my calendar and time dont change on using timetravel slider
- i cant give reminders a name
- sort the info in the weather widget more sanely, same for system stats. keep related close
- in network widget, above tunnels, create new section "FIREWALL" where you can quick select all 3 modes instead of cycling
- on display, remove red and only show nightmode with no icon in front, put monitors topmost after birghtness and before
  colorgrading
- the notifcation bell should always be one color and show a dot if there are notifs, and strike through if dnd
- the default notification window needs to have a little bit more height when empty to not cut off whats written there
- settings menu kinda laggy
- in the install step, in the blue menu, you have to click platform twice (so luca-pc/note...) because it weirdly hangs?
- firefox should never show "import bookmarks"
- applying colortheme still takes very long
- projects folder is missing in the file explorer bookmarks
- remove the steam .desktop thing on the actual desktop when installing
- between plymouth and ly is a short black screen with tex on it.
- in plasma: Ksplash service failed: journalctl --user -xeu dbus-:1.1-org.kde.KSplash@0.service
- i dont see WOL in bios, can you enable it software side? its supported (by internet research)
- can we get autocomplete in shell for dot file
- in nvim the icons for hidden and gitignored are two different eyes.. make that coherent
- sometimes an error overlaps into the ly password bar, it reads: Bluetooth hci0: reading supported features failed
- mod shift e exit does exit not exit, it leaves behind a hyprland session where i am then stuck in
- why does the header of firefox (so everything not the page) look so much better in plasma than in hyprland
- weather shows ERR when booting.
- idle ram is quite high
- in okular: Could not print the document. Detailed error is "Printing process could not start". Please report to bugs.kde.org
- fans are quite loud in idle on my pc, check
- initial unreal window is too small, then scaled up and then clipped so i need to manually resize it everytime
- add a formfactor/profile thingy for server, where its a bare minimum hardened empty server with just docker
- still too many comments scattered across the source code
- is the settings menu truely working for all things?
- why is there are latex_snippets.lua and a snippets.lua ???? make a snippets/ folder. dont do these kinds of stupid mistakes
- nvim doesnt have support for PKGBUILD files
- opening emacs fucking flashbangs me with pure white
- do i have all symbols i need on my split keyboard config?
- nvim: /usr/src/debug/neovim/neovim/src/nvim/grid.c:672: grid_put_linebuf: Assertion `0 <= row && row < grid->rows' failed.
- is there a way to save noscript allows somewhere?
- firefox shows "you cant use speech synthess because speech dispatcher wont open"
- add this https://k6.io/open-source/

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
