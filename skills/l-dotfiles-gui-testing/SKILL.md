---
name: l-dotfiles-gui-testing
description: "The one procedure for launching an app or game only to screenshot or check it: an own headless output, muted audio, nested Hyprland or Plasma, a test quickshell, teardown. On Hyprland 0.57 an output can kill Luca's live apps, so ask him first. Load before starting any GUI program he is not watching. Acting on his screen for him: l-dotfiles-desktop-control."
---

# gui-testing

A program launched only to check something never shows on Luca's monitors unless he says so. Default: a headless output
of the agent's own, created only after he agreed. With his explicit permission (he is away, "use the pc") his real
monitors are the other path.

## Never

- Create an output on the live compositor without asking Luca: on Hyprland 0.57, `hyprctl output create headless` (and
  a nested Hyprland on it) once killed his live neovide, Firefox, ghostty and quickshell within seconds
  (`unknown object (N), message attach(?oii)` in the compositor log).
- `hyprctl keyword monitor`, `hl.monitor`, a monitor rule or position on the live compositor: an auto-positioned output
  follows the rightmost one and can push a real monitor off-screen. Create the headless output and nothing else.
- Bare `grim`: it captures the headless areas too. Always `grim -o <output>`.
- Arm a window rule, an `hl.on` handler or a keybind that acts on windows (close, move, float, fullscreen) on the live
  compositor before it passed in a nested Hyprland ([nested.md](nested.md)): `dot apply desktop/hyprland` arms it on
  every window Luca opens.
- A Flatpak or other xdg-desktop-portal app on a headless output of the live session: an output removed under an open
  portal dialog hangs xdg-desktop-portal-kde and freezes every file dialog in the session. Such apps run only in a
  nested Hyprland ([nested.md](nested.md)).
- Remove an output or sink you did not create; restart a failed user `xdg-document-portal.service` (status 21, left by
  a nested Hyprland on the real runtime dir): tell Luca instead.

## Procedure

Copy this checklist and tick it off:

```
- [ ] Luca agreed
- [ ] output and null sink created, name, id, workspace and module index noted
- [ ] app launched by pid, its window on my output, grim -o taken
- [ ] nested teardown (if used), per-agent app state removed
- [ ] teardown done, portal ping answers
```

```bash
hyprctl monitors -j | jq -r '.[].name'                 # before
hyprctl output create headless
hyprctl monitors -j | jq -r '.[] | select(.name | startswith("HEADLESS")) | "\(.name) \(.id) \(.activeWorkspace.id)"'
pactl load-module module-null-sink sink_name=agent-null    # keep the printed module index
```

The name missing from the before list is yours: `HEADLESS-N`, its id and workspace `<ws>`. `exec_cmd` returns no pid,
so `sh -c` writes its own pid and `exec`s the app (the second argument is window rules; an unknown effect is refused):

```bash
pidfile=/tmp/<agent>-app.pid
hyprctl dispatch "hl.dsp.exec_cmd('sh -c \"echo \$\$ > $pidfile; exec env PULSE_SINK=agent-null <app>\"', { workspace = '<ws> silent' })"
pid=$(cat $pidfile)
hyprctl clients -j | jq --argjson pid "$pid" '.[] | select(.pid == $pid) | {class, title, monitor, workspace: .workspace.name}'
grim -o HEADLESS-N /tmp/<agent>-shot.png
```

- Confined apps write only where their AppArmor profile allows: zathura `-c ~/.config/zathura/<agent>`, chromium
  `--user-data-dir /tmp/.org.chromium.Chromium.<agent>`.
- `monitor` must be your output's id. A window on a physical monitor is killed by PID at once and the launch fixed,
  never moved by focusing it.
- An app that forks its window off a launcher (electron, steam, flatpak) has another pid: find it by class or title
  against a `hyprctl clients -j` from before the launch.
- Re-exec wrappers, splash-then-main apps and parentless X11 dialogs escape the workspace rule: [nested.md](nested.md),
  read it before launching LibreOffice, GIMP, HexChat, a portal app, a nested Plasma or a test quickshell.

## Teardown

Nested run: do the [nested.md](nested.md) teardown first.

```bash
kill $pid; rm $pidfile
pactl unload-module <index>
hyprctl output remove HEADLESS-N
busctl --user call org.freedesktop.impl.portal.desktop.kde /org/freedesktop/portal/desktop org.freedesktop.DBus.Peer Ping
```

The portal ping must answer; if it hangs, tell Luca. Remove the per-agent state (`~/.config/zathura/<agent>`,
`/tmp/.org.chromium.Chromium.<agent>`, `~/.config/libreoffice/<agent>`, zathura's
`~/.local/share/zathura/bookmarks.sqlite`) with the test files.

## Luca's monitors, with his permission

- Screens off: `hyprctl dispatch "hl.dsp.dpms({ mode = 'on' })"`; off again when done.
- The desktop under the windows: move an empty workspace onto the main monitor
  (`hl.dsp.workspace.move({ monitor = 'DP-2' })` while it is focused), then put workspace 1 back.
- hypridle locks after the `desktop/hyprland.idle_lock_s` option without input; IPC calls and screenshots are no input.
  `toggle-keep-awake.nu` holds it off (`agent-guard` only blocks suspend). A lock needs Luca's login: stop there.
- `grim -o <output>` of a real monitor captures whatever he has open: crop to what the check needs.
