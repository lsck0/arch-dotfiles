# desktop/hyprland

- `hyprland.lua` requires each `hyprland_*.lua` (`powersave` last, it overrides the rest).
- `platform.lua` is generated from the module's options (monitors, workspaces, xwayland scale, keyboard from
  `00-keyboard.conf`); per-machine behavior comes from there, never a hostname check (`l-dotfiles-platform-facts`).
- Config and dispatch are Lua: `hyprctl dispatch "hl.dsp.exec_cmd('cmd')"`; `hyprctl dispatch exec cmd` fails.
  API stub: `hl.meta.lua`.
- `plugins.nu` builds the plugins per user against the package headers, no hyprpm. `lid.nu` turns the internal panel
  off while the lid is closed and an external monitor is on.
- `GDK_SCALE` (`xwayland_scale`) reaches GTK only, never `Xft.dpi` (GTK would double its fonts). Every other xwayland
  toolkit gets its own scale: Qt5 xcb `QT_SCALE_FACTOR` (`base/v4l-utils/qvidcap.sh`, `programming/renderdoc`), Tk
  `tk scaling` (`desktop/applications/gitk.tcl`, `idle.py`), wine `LogPixels` (`desktop/applications/mod.nu`), plain
  Xft the point size (`desktop/nsxiv`), a pkexec'd root GTK app its own `GDK_SCALE` (`desktop/gparted/gparted-run.sh`),
  ONLYOFFICE `force-scale` (`desktop/applications/mod.nu`).
- An edit lands with `dot apply desktop/hyprland`.
