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
- Otherwise a nested Hyprland on your workspace (about 940x490 on a scale-2 headless output). It runs on a private
  runtime dir `$rt` that links only the outer compositor's socket and pulse, so the compositor, its `dbus-run-session`
  portals (`$rt/doc`) and everything started inside stay off the user's `/run/user/$UID`. Keep the path short: a
  socket path over 108 bytes fails, so never the scratchpad. A window rule under test goes into its config:

```bash
rt=/run/user/$UID/ag-<agent>; mkdir -m 700 $rt
ln -s $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY.lock $XDG_RUNTIME_DIR/pulse $rt/
cat > /tmp/<agent>-nested.lua <<'EOF'
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true }, ecosystem = { no_update_news = true } })
EOF
hyprctl dispatch "hl.dsp.exec_cmd('sh -c \"exec env -u HYPRLAND_INSTANCE_SIGNATURE -u DISPLAY XDG_RUNTIME_DIR=$rt dbus-run-session Hyprland -c /tmp/<agent>-nested.lua\"', { workspace = '<ws> silent' })"
nested=$(ls $rt/hypr)
XDG_RUNTIME_DIR=$rt HYPRLAND_INSTANCE_SIGNATURE=$nested hyprctl dispatch "hl.dsp.exec_cmd('env PULSE_SINK=agent-null <app>')"
XDG_RUNTIME_DIR=$rt HYPRLAND_INSTANCE_SIGNATURE=$nested hyprctl clients -j | jq '.[] | {class, title, pid, at, size}'
```

- `wayland-<n>` below is the nested compositor's own socket: the one in `$rt` you did not link.
- A QML test runs a trimmed shell copy inside (`quickshell -p <copy>`, a `shell.qml` with only the plugin), started and
  called as in the next section.
- The nested compositor is the `aquamarine` client in the outer `hyprctl clients -j`: check its `monitor` is your
  output's id, as for any app, kill the apps inside, then it.
- Confined apps write only where their AppArmor profile allows: zathura's `-c` as `~/.config/zathura/<agent>`, chromium's
  `--user-data-dir` as `/tmp/.org.chromium.Chromium.<agent>`. Remove state an app keeps across runs (zathura's
  `~/.local/share/zathura/bookmarks.sqlite`) with the test files.

## Test quickshell: private runtime dir

The shell keeps state under `$XDG_RUNTIME_DIR` (`quickshell/`, `toggles/`, cava's config). `Lock.qml` writes its
crash-recovery marker `$XDG_RUNTIME_DIR/quickshell/locked` while locked: a test shell on the real runtime dir that
locks and is killed leaves `/run/user/$UID/quickshell/locked`, and the user's live shell locks the screen on its next
start. A test quickshell runs only inside the nested `dbus-run-session` Hyprland, which hands it `$rt` (a private
runtime dir keeps it off the user's state, not off the user's session bus: `l-dotfiles-quickshell-dev`).

```bash
qspidfile=/tmp/<agent>-qs.pid
XDG_RUNTIME_DIR=$rt HYPRLAND_INSTANCE_SIGNATURE=$nested hyprctl dispatch "hl.dsp.exec_cmd('sh -c \"echo \$\$ > $qspidfile; exec env PULSE_SINK=agent-null quickshell -p <copy>\"')"
XDG_RUNTIME_DIR=$rt WAYLAND_DISPLAY=wayland-<n> qs ipc -p <copy> call lock isLocked
```

`qs ipc` for that shell needs both its `XDG_RUNTIME_DIR` and its `WAYLAND_DISPLAY`. `pipewire-0` stays unlinked: the
audio widgets stay empty (`Failed to connect pipewire context`), and linking it hands the test shell the user's real
audio graph. A `/run/user/$UID/quickshell/locked` you find was left by a test: remove it only after `qs ipc -p
~/.config/quickshell call lock isLocked` prints `false` for the user's shell.

## Teardown

```bash
kill $pid; rm $pidfile
pactl unload-module <index>
hyprctl output remove HEADLESS-N
```

Only your own output and sink. A killed test quickshell leaves every helper it started running, reparented to
`systemd --user`: take `pgrep -P $(cat $qspidfile)` before `kill $(cat $qspidfile)`, then kill by PID the ones still
alive. No nested Hyprland outlives the test. Then `rm -r $rt $qspidfile` (a still mounted `$rt/doc` first
`fusermount3 -u $rt/doc`), and with the test files the per-agent app state:
`rm -r ~/.config/libreoffice/<agent> ~/.config/zathura/<agent>` and zathura's `bookmarks.sqlite`.

A failed user `xdg-document-portal.service` (status 21) is left by a nested Hyprland that ran on the real runtime dir:
tell Luca, never restart it yourself.
