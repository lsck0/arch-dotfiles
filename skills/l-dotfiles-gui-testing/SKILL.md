---
name: l-dotfiles-gui-testing
description: The one procedure for launching an app, game, editor or viewer only to screenshot or check it, on a headless Hyprland output of the agent's own, with muted audio and clean teardown. Load before any agent starts a GUI program the user is not watching.
---

# gui-testing

A program launched only to verify something never shows on the user's monitors. Each agent makes its own headless
output, uses it, and removes it; several agents can do this at once.

## Never

- `hyprctl keyword monitor`, `hl.monitor`, a monitor rule or a position: an agent once moved DP-2 off-screen this way,
  and an auto-positioned output follows the rightmost one, so a headless output is created and nothing else.
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

## Teardown

```bash
kill $pid; rm $pidfile
pactl unload-module <index>
hyprctl output remove HEADLESS-N
```

Remove only your own output and sink; leave every other `HEADLESS-*`.
