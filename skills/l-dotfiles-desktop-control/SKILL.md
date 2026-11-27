---
name: l-dotfiles-desktop-control
description: "Acting on Luca's live Hyprland desktop the way his keys and bar do: urls and apps, windows and workspaces, media, volume, brightness, notifications, toggles (route, vpn, dnd, night light), quickshell panels, tasks, reminders, notes, screenshots, typing. Load when Luca asks an agent to do something on his screen. Launching only to check: l-dotfiles-gui-testing; changing the shell: l-dotfiles-quickshell-dev."
---

# desktop-control

Everything here acts on the session Luca sees: do what he asked, nothing beside it, and say what you did. Configuring
the machine still goes through `l-dotfiles`; this skill is for using it.

## Rules

- Act only on a clear ask. Never close, kill or move a window, end media or change a toggle he did not name.
- Toggles with security weight (`toggle-route`, `toggle-vpn`, `toggle-firewall`, `toggle-trust-network`,
  `toggle-portal`, `toggle-anonymous-socks`): repeat the change back and wait for his yes.
- Never type passwords or secrets, never answer a sudo, polkit or YubiKey prompt: those are his. A toggle with a root
  half fails without his touch: report it, never retry around it.
- Screens off (`dpmsStatus` false in `hyprctl monitors -j`) or the lock up (`qs ipc -p ~/.config/quickshell call lock
  isLocked` prints `true`): he is away. Queue the request and tell him; never unlock or wake.

## Open things

| ask | command |
|---|---|
| a url | `xdg-open '<url>'` (a new tab in the running Firefox) |
| an app | `uwsm app -- <command>` or `uwsm app -- <id>.desktop` (its own scope, like his launcher) |
| a file or folder | `xdg-open <path>` |
| a startpage link | the `lab-<route>` commands in `~/.local/bin` (`lab-grafana`, `lab-mirror`, ...) |

## Windows and workspaces

Dispatchers are Lua: `hyprctl dispatch '<lua>'`.

```bash
hyprctl clients -j | jq '.[] | {class, title, address, workspace: .workspace.id}'   # what is open
hyprctl dispatch 'hl.dsp.focus({ window = "address:0x..." })'
hyprctl dispatch 'hl.dsp.focus({ workspace = 6 })'
hyprctl dispatch 'hl.dsp.window.move({ workspace = "3", follow = false, window = "address:0x..." })'
hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })'
hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })'
```

Workspace to monitor: `desktop/hyprland.workspaces` in `platforms/luca-pc.options.nuon`. Closing a window, only when he
asked: focus it, then `$DOTFILES/configs/desktop/hyprland/scripts/window-close.nu` (acts on the focused one).

## Media, sound, screen

- `media-key play-pause|next|previous|stop|volume-up|volume-down|volume-mute|mic-mute|brightness-up|brightness-down`:
  as his keys, with the OSD. `playerctl -l` lists players.
- Exact values: `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.4` (or `5%+`), `wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle`,
  the mic is `@DEFAULT_AUDIO_SOURCE@`; `monitor-brightness get <output>`, `monitor-brightness set <output> <percent>`.
- Look at the screen: `grim -o DP-2 /tmp/shot.png` (main) or `-o DP-1`, cropped to what you need: it shows whatever he
  has open. His own screenshots land in `~/pictures/screenshots` and the clipboard.

## The shell

- `qs ipc -p ~/.config/quickshell show` lists targets. Panels: `call bar list`, then `call bar toggle <panel>`. The
  launcher on a mode: `call appsearch openWith '+ '`.
- Notify him: `notify-send -a system-agent '<title>' '<body>'` (dnd holds it). Every toast into history: `call
  notifications dismissAll`.

## Toggles

`$DOTFILES/scripts/toggles/status.nu` prints every state as JSON; read it before and after. Each toggle is
`$DOTFILES/scripts/toggles/toggle-<name>.nu`: on/off ones take `on|off|toggle`, n-state ones `set <value>` or the state
as a subcommand (route `direct|proton|tor|offline`, firewall `permissive|default|restrictive`, powermode
`auto|balanced|performance|power-saver`).

## Tasks, reminders, notes

- Task: `capture task <words>` (taskwarrior syntax: `project:`, `due:`, `scheduled:`, `priority:H`, `+tag`); query with
  `task next`.
- Reminder: `capture remind <90|10m|2h|1h30m|15:00> <message>`; `reminder list --json`, `reminder cancel <unit>`. They
  survive suspend and reboot. A fired card: `call alert dismiss` or `call alert snooze <minutes>` (the newest).
- Note: `capture note <words>` appends to `~/sync/notes/inbox.md`.
- His agenda's calendar: `task-calendar events`.

## Typing and acting inside a window

`wtype '<text>'` types into whatever has focus; `wtype -k Return` sends a key, `wtype -M ctrl l -m ctrl` a chord. Never a
SUPER chord through wtype: its virtual keyboard's first key goes out as keycode 9, Hyprland matches binds by keycode, so
`wtype -M logo -k F1` ran SUPER+Escape and locked the screen; reach a bind's action through `hyprctl dispatch` or `qs ipc`. Check
the focused window first (`hyprctl activewindow -j`); never type into a terminal or a password field. No pointer
automation: `ydotool.service` runs only while `mouse-jittering` does. `dictate` (`SUPER+ALT+v`) is his voice, not an
agent's tool.

Inside an app or page, in this order, saying which before you start:

1. The app's HTTP API where it has one (ComfyUI).
2. Firefox's web console: ctrl+l, ctrl+shift+k, one short line, Enter; F12 closes it.

Does not work: keys typed at a page hit its shortcuts unless a text field has focus; Firefox blocks `javascript:` in the
address bar; a GTK portal file dialog ignores Enter from `wtype`.
