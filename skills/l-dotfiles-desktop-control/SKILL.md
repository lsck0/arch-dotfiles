---
name: l-dotfiles-desktop-control
description: "Driving Luca's live Hyprland desktop the way he does with keys and the bar: open a url or app, move and focus windows, workspaces, media and volume, notifications, toggles (trust network, route incl. tor, vpn, dnd, night light), quickshell panels, tasks, reminders and notes, screenshots, typing text, acting inside a browser page. Load when Luca asks an agent in his session (the system agent above all) to do something on his screen. Launching a program only to check it is l-dotfiles-gui-testing; changing the shell itself is l-dotfiles-quickshell-dev."
---

# desktop-control

Everything here acts on the session Luca sees: do what he asked, nothing beside it, and say what you did. Machine
changes still go through the dotfiles (`l-dotfiles`); this skill is for using the machine, not configuring it.

## Rules

- Act only on a clear ask. Never close, kill or move a window, end media or change a toggle he did not name.
- Toggles with security weight (`toggle-route`, `toggle-vpn`, `toggle-firewall`, `toggle-trust-network`,
  `toggle-portal`, `toggle-anonymous-socks`): repeat the change back and wait for his yes before running it.
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

Which workspace sits on which monitor: `desktop/hyprland.workspaces` in `platforms/luca-pc.options.nuon`. Closing a window:
`$DOTFILES/configs/desktop/hyprland/window-close.nu` acts on the focused one; focus it first, and only when he asked.

## Media, sound, screen

- Playback: `media-key play-pause|next|previous|stop` (the bar's player, with the OSD; playerctl's first player while
  the shell is down); `playerctl -l` lists players.
- Volume: `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+` (or `-`, or `0.4`), mute `wpctl set-mute @DEFAULT_AUDIO_SINK@
  toggle`; the mic is `@DEFAULT_AUDIO_SOURCE@`. With the OSD, as his keys: `media-key volume-up|volume-down|
  volume-mute|mic-mute`.
- Brightness: `media-key brightness-up|brightness-down`, or `monitor-brightness get <output>` and `set <output>
  <percent>` (ddc on the desktop monitors).
- Screenshot to look at the screen: `grim -o DP-2 /tmp/shot.png` (main) or `-o DP-1`; crop to what you need, it
  shows whatever he has open. His own (Print or SUPER+SHIFT+s, SHIFT+Print, SUPER+Print) land in
  `~/pictures/screenshots` and the clipboard.

## The shell (quickshell)

- `qs ipc -p ~/.config/quickshell show` lists the targets. Panels: `qs ipc -p ~/.config/quickshell call bar toggle
  <panel>`; `call bar list` prints the panels there are now (clock, weather, homelab, system, network,
  display, audio-io, notifications, agents; media and discord only while they show). The launcher on a mode: `call
  appsearch openWith '+ '`.
- Notify him: `notify-send -a system-agent '<title>' '<body>'` (shown in the bar; dnd holds it). Close every toast
  on screen into history: `call notifications dismissAll` (his `SUPER+SHIFT+d`).

## Toggles

`scripts/toggles/status.nu` prints every toggle's state as JSON. Each is `$DOTFILES/scripts/toggles/toggle-<name>.nu`: on/off
ones take `on|off|toggle`, n-state ones `set <value>` or the state itself (route `direct|proton|tor|offline`, firewall
`permissive|default|restrictive`, powermode `auto|balanced|performance|power-saver`). Read the status before and after; a toggle
with a root half asks for Luca's touch and fails without him: report that, never retry around it.

## Tasks, reminders, notes

- Task: `capture task <words>` (taskwarrior syntax: `project:`, `due:`, `scheduled:`, `priority:H`, `+tag`); query
  with `task next`.
- Reminder: `capture remind <90|10m|2h|1h30m|15:00> <message>`; `reminder list --json` and `reminder cancel <unit>`
  for the pending ones. They survive suspend and reboot (records in `$XDG_STATE_HOME/quickshell/reminders`). A fired
  one's card: `qs ipc -p ~/.config/quickshell call alert dismiss` or `call alert snooze <minutes>` (the newest card).
- Note: `capture note <words>` appends to `~/sync/notes/inbox.md`.
- His agenda's calendar: `task-calendar events`.

## Typing and acting inside a window

`wtype '<text>'` types into whatever has focus (a chat box, a form); `wtype -k Return` sends a key, `wtype -M ctrl l
-m ctrl` a chord. Check the focused window first (`hyprctl activewindow -j`), and never into a terminal or a password
field. There is no pointer automation (no ydotoold). His dictation (`dictate`, `SUPER+ALT+v`) records on the first
press and types the transcript on the second: his voice, not an agent's tool.

Acting inside an app or a page, in this order, and say which before you start:

1. The app's HTTP API where it has one (ComfyUI).
2. In Firefox, the web console: focus the address bar (ctrl+l), ctrl+shift+k, type one short line, Enter, F12 closes
   it.

What does not work: keys typed at a page land on the page's own shortcuts unless a text field has focus; Firefox
blocks `javascript:` in the address bar; a GTK portal file dialog did not take Enter from `wtype`.
