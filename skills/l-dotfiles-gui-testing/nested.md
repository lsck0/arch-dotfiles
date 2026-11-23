# Apps that escape the exec rule, nested sessions, a test quickshell

The workspace rule holds only for what the started pid maps. Re-exec wrappers (`soffice`, `dbus-run-session`, any
launcher that forks), splash then main window (GIMP) and parentless X11 dialogs (HexChat's Network List at global 0,0)
can land on Luca's screen. Exec the GUI binary itself; a bus it needs is started beforehand, never wrapped around it.

## The real binary

LibreOffice: `/usr/lib/libreoffice/program/soffice.bin --writer
-env:UserInstallation=file://$HOME/.config/libreoffice/<agent>`; a fresh profile exits once to restart, so launch twice.

## Nested Hyprland

On your headless workspace (about 940x490 on a scale-2 output). It runs on a private runtime dir `$rt` that links only
the outer compositor's socket and pulse, so the compositor, its private dbus-daemon on `$rt/bus`, its portals
(`$rt/doc`) and everything started inside stay off Luca's `/run/user/$UID`. A socket path over 108 bytes fails, so keep
`$rt` short (never the scratchpad). A window rule under test goes into the nested config.

```bash
rt=/run/user/$UID/ag-<agent>; mkdir -m 700 $rt
ln -s $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY.lock $XDG_RUNTIME_DIR/pulse $rt/
cat > /tmp/<agent>-nested.lua <<'EOF'
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true }, ecosystem = { no_update_news = true } })
EOF
XDG_RUNTIME_DIR=$rt dbus-daemon --session --fork --print-pid --address=unix:path=$rt/bus > $rt/dbus.pid
hyprctl dispatch "hl.dsp.exec_cmd('sh -c \"exec env -u HYPRLAND_INSTANCE_SIGNATURE -u DISPLAY XDG_RUNTIME_DIR=$rt DBUS_SESSION_BUS_ADDRESS=unix:path=$rt/bus Hyprland -c /tmp/<agent>-nested.lua\"', { workspace = '<ws> silent' })"
timeout 10 sh -c "until [ -S $rt/hypr/*/.socket.sock ]; do sleep 0.2; done"
nested=$(ls $rt/hypr)
XDG_RUNTIME_DIR=$rt HYPRLAND_INSTANCE_SIGNATURE=$nested hyprctl dispatch "hl.dsp.exec_cmd('env PULSE_SINK=agent-null <app>')"
XDG_RUNTIME_DIR=$rt HYPRLAND_INSTANCE_SIGNATURE=$nested hyprctl clients -j | jq '.[] | {class, title, pid, at, size}'
```

- The nested compositor is the `aquamarine` client in the outer `hyprctl clients -j`: check its `monitor` is your
  output's id, as for any app.
- `wayland-<n>` below is the nested compositor's own socket: the one in `$rt` you did not link.

## Nested Plasma

`kwin_wayland --width W --height H --xwayland --socket <name> --exit-with-session plasmashell`, exec'd directly the same
way on the same `$rt` and private bus. KWin and plasmashell rewrite `~/.config/{kwinrc,kglobalshortcutsrc,
kwinoutputconfig.json,plasma-org.kde.plasma.desktop-appletsrc,kcminputrc,kdeglobals,plasmashellrc}`: `cp -a` them
aside first and restore them after teardown. Its `kdeconnectd`, `kactivitymanagerd` and `xdg-desktop-portal-kde`
outlive it: kill them by PID.

## Test quickshell

Only inside the nested Hyprland, which hands it `$rt`. On the real runtime dir a test shell that locks and is killed
leaves `/run/user/$UID/quickshell/locked`, and Luca's live shell locks his screen on its next start. Run a trimmed copy
(a `shell.qml` with only the plugin under test):

```bash
qspidfile=/tmp/<agent>-qs.pid
XDG_RUNTIME_DIR=$rt HYPRLAND_INSTANCE_SIGNATURE=$nested hyprctl dispatch "hl.dsp.exec_cmd('sh -c \"echo \$\$ > $qspidfile; exec env PULSE_SINK=agent-null quickshell -p <copy>\"')"
XDG_RUNTIME_DIR=$rt WAYLAND_DISPLAY=wayland-<n> qs ipc -p <copy> call lock isLocked
```

- `qs ipc` for it needs both its `XDG_RUNTIME_DIR` and its `WAYLAND_DISPLAY`.
- Leave `pipewire-0` unlinked: audio widgets stay empty (`Failed to connect pipewire context`); linking it hands the
  test shell Luca's real audio graph.
- A `/run/user/$UID/quickshell/locked` you find was left by a test: remove it only after
  `qs ipc -p ~/.config/quickshell call lock isLocked` prints `false` for his shell.

## Nested teardown

1. A killed test quickshell leaves its helpers running under `systemd --user`: `pgrep -P $(cat $qspidfile)` first, then
   `kill $(cat $qspidfile)`, then kill the listed PIDs still alive.
2. Kill the apps inside, then the nested compositor; none outlives the test.
3. Nested Plasma: kill `kdeconnectd`, `kactivitymanagerd` and `xdg-desktop-portal-kde` by PID; restore the saved
   `~/.config` KDE files.
4. `kill $(cat $rt/dbus.pid)`; `fusermount3 -u $rt/doc` if still mounted; `rm -r $rt $qspidfile`.
5. Then the outer teardown in SKILL.md.
