# desktop/hyprland

- `hyprland.lua` requires each `hyprland_*.lua` (`powersave` last, it overrides the rest).
- `platform.lua` is generated from the module's options (monitors, workspaces, xwayland scale, keyboard from
  `00-keyboard.conf`); per-machine behavior comes from there, never a hostname check (`l-dotfiles-platform-facts`).
- Config and dispatch are Lua: `hyprctl dispatch "hl.dsp.exec_cmd('cmd')"`; `hyprctl dispatch exec cmd` fails.
  API stub: `hl.meta.lua`.
- `plugins.nu` builds the plugins per user against the package headers, no hyprpm. `lid.nu` turns the internal panel
  off while the lid is closed and an external monitor is on.
- X11 apps scale through `GDK_SCALE` only (`xwayland_scale`); no `Xft.dpi`, GTK would double its fonts.
- An edit lands with `dot apply desktop/hyprland`.
