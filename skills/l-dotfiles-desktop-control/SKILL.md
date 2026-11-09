---
name: l-dotfiles-desktop-control
description: "Driving Luca's live Hyprland desktop the way he does with keys and the bar: open a url or app, move and focus windows, workspaces, media and volume, notifications, toggles (trust network, route, tor, vpn, dnd, night light), quickshell panels, tasks, reminders and notes, screenshots, typing text. Load when Luca asks an agent in his session (the system agent above all) to do something on his screen."
---

# desktop-control

Everything here acts on the session Luca sees: do what he asked, nothing beside it, and say what you did. Machine
changes still go through the dotfiles (`l-dotfiles`); this skill is for using the machine, not configuring it.

## Rules

- Act only on a clear ask. Never close, kill or move a window, end media or change a toggle he did not name.
- Toggles with security weight (`toggle-route`, `toggle-vpn`, `toggle-firewall`, `toggle-trust-network`,
  `toggle-portal`): repeat the change back and wait for his yes before running it.
- Never type passwords or secrets, never answer a sudo, polkit or YubiKey prompt: those are his.
- Screens off (`dpmsStatus` false in `hyprctl monitors -j`) or the lock up (`qs ipc -p ~/.config/quickshell call lock
  isLocked` prints true): he is away; queue the request and tell him, never unlock or wake.

## Open things

| ask | command |
|---|---|
| a url in the browser | `xdg-open '<url>'` (firefox; a new tab in the running one) |
| an app | `uwsm app -- <command>` (its own scope, like his launcher); `.desktop` ids: `uwsm app -- <id>.desktop` |
| a file or folder | `xdg-open <path>` |
| his startpage links | the `lab-<route>` and link commands in `~/.local/bin` (`lab-grafana`, `lab-mirror`, ...) |

## Windows and workspaces

Hyprland's dispatchers are Lua: `hyprctl dispatch '<lua>'`.

```bash
hyprctl clients -j | jq '.[] | {class, title, address, workspace: .workspace.id}'   # what is open
hyprctl dispatch 'hl.dsp.focus({ window = "address:0x..." })'
hyprctl dispatch 'hl.dsp.focus({ workspace = 6 })'
hyprctl dispatch 'hl.dsp.window.move({ workspace = "3", follow = false, window = "address:0x..." })'
hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })'
hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })'
```

Workspaces 1 to 4 are on DP-2 (main), 5 to 10 on DP-1. Closing a window: `$DOTFILES/configs/desktop/hyprland/window-close.nu`
acts on the focused one; focus it first, and only when he asked.

## Media, sound, screen

- Playback: `media-key play-pause|next|previous` (the bar's player); `playerctl -l` lists players.
- Volume: `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+` (or `-`, or `0.4`), mute `wpctl set-mute @DEFAULT_AUDIO_SINK@
  toggle`; the mic is `@DEFAULT_AUDIO_SOURCE@`.
- Brightness: `monitor-brightness` (ddc on the desktop monitors).
- Screenshot to look at the screen: `grim -o DP-2 /tmp/shot.png` (main) or `-o DP-1`; crop to what you need, it
  shows whatever he has open.

## The shell (quickshell)

- `qs ipc -p ~/.config/quickshell show` lists the targets. Panels: `qs ipc -p ~/.config/quickshell call bar toggle
  <panel>` (audio, notifications, clock, display, homelab, agents, media, network, obs, system, weather); the
  launcher on a mode: `call appsearch openWith '+ '`.
- Notify him: `notify-send -a system-agent '<title>' '<body>'` (shown in the bar; dnd holds it).

## Toggles

`scripts/toggles/status.nu` prints every toggle's state as JSON. Each is `toggle-<name>.nu [on|off|toggle]` in
`$DOTFILES/scripts/toggles/` (route takes direct, proton, tor, offline). Read the status before and after; a toggle
with a root half asks for Luca's touch and fails without him: report that, never retry around it.

## Tasks, reminders, notes

- Task: `capture task <words>` (taskwarrior syntax: `project:`, `due:`, `scheduled:`, `priority:H`, `+tag`); query
  with `task next`.
- Reminder: `capture remind <90|10m|2h|1h30m> <message>`.
- Note: `capture note <words>` appends to `~/sync/notes/inbox.md`.
- His agenda's calendar: `task-calendar events`.

## Typing into the focused window

`wtype '<text>'` types into whatever has focus (a chat box, a form). Check the focused window first
(`hyprctl activewindow -j`), and never into a terminal or a password field.
