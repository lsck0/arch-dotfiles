---
name: l-dotfiles-gui-testing
description: The one procedure for launching an app, game, editor or viewer only to screenshot or check it, on a headless Hyprland output of the agent's own, with muted audio and clean teardown. Load before any agent starts a GUI program the user is not watching.
---

# gui-testing

A program launched only to verify something never shows on the user's monitors. Each agent makes its own headless
output, uses it, and removes it; several agents can do this at once.

## Never

- `hyprctl keyword monitor`, `hl.monitor`, a monitor rule or a position: an agent once moved DP-2 off-screen this way,
  and an auto-positioned output follows the rightmost one, so a headless output is created and nothing else (a
  nested Hyprland's own config, below, is the one place for `hl.monitor`).
- Bare `grim`: it captures the headless areas too. Always `grim -o HEADLESS-N`.
- `pkill -f <pattern>`: the pattern matches the agent's own shell. Kill by PID.
- Removing an output you did not create (another agent's `HEADLESS-2`, say).

## Procedure

```bash
hyprctl monitors -j | jq -r '.[].name'                 # before
hyprctl output create headless
hyprctl monitors -j | jq -r '.[] | select(.name | startswith("HEADLESS")) | "\(.name) \(.id) \(.activeWorkspace.id)"'
```

The new name (not in the before list) is yours: `HEADLESS-N`, its monitor id and active workspace `<ws>`.

Mute test audio:

```bash
pactl load-module module-null-sink sink_name=agent-null    # prints the module index, keep it
```

Launch onto that workspace with `PULSE_SINK=agent-null` in the program's environment. `exec_cmd` returns no pid, so
the command runs under `sh -c` that writes its own pid and then `exec`s the app in place (the second argument is
window rules for what it opens; an unknown effect is refused). Then verify the placement before capturing:

```bash
pidfile=/tmp/<agent>-app.pid
hyprctl dispatch "hl.dsp.exec_cmd('sh -c \"echo \$\$ > $pidfile; exec env PULSE_SINK=agent-null <app>\"', { workspace = '<ws> silent' })"
pid=$(cat $pidfile)
hyprctl clients -j | jq --argjson pid "$pid" '.[] | select(.pid == $pid) | {class, title, monitor, workspace: .workspace.name}'
```

An app that forks its window off a launcher (electron, steam, flatpak) has another pid: find it by class or title
instead (`select(.class == "<class>")`, compared with a `hyprctl clients -j` from before the launch) and take its
`.pid`. `monitor` must be your output's id. A window that landed on a physical monitor is killed at once (by PID)
and the launch fixed, never moved there by focusing it. Then capture and read the image:

```bash
grim -o HEADLESS-N /tmp/<agent>-shot.png
```

## Apps that escape the exec rule

The workspace rule holds only for what the started pid maps. A wrapper that re-execs (LibreOffice's `soffice`), an
app with a splash and then its main window (GIMP), a second toplevel or an X11 dialog with no parent (HexChat's
Network List maps at global 0,0, the corner of the user's monitor, though its workspace is yours) can land on the
user's screen. Two reliable paths:

- The real binary, where one exists. LibreOffice: `/usr/lib/libreoffice/program/soffice.bin --writer
  -env:UserInstallation=file://$HOME/.config/libreoffice/<agent>`, a throwaway profile; a fresh profile's first start
  exits to restart itself, so launch it twice.
- Everything else: a nested Hyprland in a window on your workspace. All the app maps stays inside it, its output is
  the window's size (about 940x490 on a scale-2 headless output, a small screen for window rules), and a window rule
  under test goes into its minimal config:

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

`grim -o HEADLESS-N` captures it. A QML test runs a trimmed copy of the shell in there (`quickshell -p <copy>`, a
`shell.qml` with only the plugin); `qs ipc` lists only the current display's instances, so call it as
`WAYLAND_DISPLAY=wayland-<n> qs ipc -i <id> call ...`. The nested compositor is the `aquamarine` client in the outer
`hyprctl clients -j`: kill the apps inside, then its pid.

A confined app reads and writes only its own paths: a throwaway config or profile goes where its AppArmor profile allows
(zathura's `-c` under `~/.config/zathura/`, chromium's `--user-data-dir` as `/tmp/.org.chromium.Chromium.<agent>`, the
LibreOffice profile above). State the app keeps across runs (zathura's position per file content in
`~/.local/share/zathura/bookmarks.sqlite`) skews a before/after comparison and is removed with the test files.

## Teardown

```bash
kill $pid; rm $pidfile
pactl unload-module <index>
hyprctl output remove HEADLESS-N
```

Remove only your own output and sink; leave every other `HEADLESS-*`.

A nested session's `dbus-run-session` bus starts its own portals, and its xdg-document-portal takes over the user's
FUSE mount `/run/user/$UID/doc`, so the user's one exits (status 21) and shows as a failed unit. After a nested run,
check `systemctl --user is-active xdg-document-portal.service`; when failed, `systemctl --user reset-failed` and
`start` it.
