---
name: l-dotfiles-gui-testing
description: The one procedure for launching an app, game, editor or viewer only to screenshot or check it, on a headless Hyprland output of the agent's own, with muted audio and clean teardown. Load before any agent starts a GUI program the user is not watching.
---

# gui-testing

A program launched only to check something never shows on the user's monitors. Each agent creates its own headless
output, uses it and removes it; several agents can do this at once.

## Never

- `hyprctl keyword monitor`, `hl.monitor`, a monitor rule or position: an auto-positioned output follows the rightmost
  one and can push a real monitor off-screen. Create the headless output and nothing else (a nested Hyprland's own
  config, below, is the only place for `hl.monitor`).
- Bare `grim`: it captures the headless areas too. Always `grim -o HEADLESS-N`.
- `pkill -f <pattern>`: it matches the agent's own shell. Kill by PID.
- Removing an output you did not create.

## Procedure

```bash
hyprctl monitors -j | jq -r '.[].name'                 # before
hyprctl output create headless
hyprctl monitors -j | jq -r '.[] | select(.name | startswith("HEADLESS")) | "\(.name) \(.id) \(.activeWorkspace.id)"'
pactl load-module module-null-sink sink_name=agent-null    # keep the printed module index
```

The name not in the before list is yours: `HEADLESS-N`, its id and workspace `<ws>`. `exec_cmd` returns no pid, so
`sh -c` writes its own pid and `exec`s the app (the second argument is window rules; an unknown effect is refused):

```bash
pidfile=/tmp/<agent>-app.pid
hyprctl dispatch "hl.dsp.exec_cmd('sh -c \"echo \$\$ > $pidfile; exec env PULSE_SINK=agent-null <app>\"', { workspace = '<ws> silent' })"
pid=$(cat $pidfile)
hyprctl clients -j | jq --argjson pid "$pid" '.[] | select(.pid == $pid) | {class, title, monitor, workspace: .workspace.name}'
grim -o HEADLESS-N /tmp/<agent>-shot.png
```

- An app that forks its window off a launcher (electron, steam, flatpak) has another pid: find it by class or title
  against a `hyprctl clients -j` from before the launch.
- `monitor` must be your output's id. A window on a physical monitor is killed at once by PID and the launch fixed,
  never moved by focusing it.

## Apps that escape the exec rule

The workspace rule holds only for what the started pid maps. Re-exec wrappers (`soffice`), splash then main window
(GIMP), parentless X11 dialogs (HexChat's Network List at global 0,0) can land on the user's screen. Two paths:

- The real binary. LibreOffice: `/usr/lib/libreoffice/program/soffice.bin --writer
  -env:UserInstallation=file://$HOME/.config/libreoffice/<agent>`; a fresh profile exits once to restart, so launch
  twice.
- Otherwise a nested Hyprland on your workspace (about 940x490 on a scale-2 headless output). A window rule under test
  goes into its config:

```bash
cat > /tmp/<agent>-nested.lua <<'EOF'
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true }, ecosystem = { no_update_news = true } })
EOF
ls $XDG_RUNTIME_DIR/hypr                               # before
hyprctl dispatch "hl.dsp.exec_cmd('sh -c \"exec env -u HYPRLAND_INSTANCE_SIGNATURE -u DISPLAY dbus-run-session Hyprland -c /tmp/<agent>-nested.lua\"', { workspace = '<ws> silent' })"
nested=<the new dir in $XDG_RUNTIME_DIR/hypr>
HYPRLAND_INSTANCE_SIGNATURE=$nested hyprctl dispatch "hl.dsp.exec_cmd('env PULSE_SINK=agent-null <app>')"
HYPRLAND_INSTANCE_SIGNATURE=$nested hyprctl clients -j | jq '.[] | {class, title, pid, at, size}'
```

- A QML test runs a trimmed shell copy inside (`quickshell -p <copy>`, a `shell.qml` with only the plugin); call it as
  `WAYLAND_DISPLAY=wayland-<n> qs ipc -i <id> call ...` (`qs ipc` lists only the current display's instances).
- The nested compositor is the `aquamarine` client in the outer `hyprctl clients -j`: kill the apps inside, then it.
- Confined apps write only where their AppArmor profile allows: zathura's `-c` under `~/.config/zathura/`, chromium's
  `--user-data-dir` as `/tmp/.org.chromium.Chromium.<agent>`. Remove state an app keeps across runs (zathura's
  `~/.local/share/zathura/bookmarks.sqlite`) with the test files.

## Teardown

```bash
kill $pid; rm $pidfile
pactl unload-module <index>
hyprctl output remove HEADLESS-N
```

Only your own output and sink. After a nested run, its `dbus-run-session` portals take over `/run/user/$UID/doc` and
the user's xdg-document-portal fails (status 21): check `systemctl --user is-active xdg-document-portal.service`, and
if failed, `systemctl --user reset-failed` and `start` it.
