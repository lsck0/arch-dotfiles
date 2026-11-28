# desktop/hyprland

- `config/hyprland.lua` requires each `hyprland_*.lua` (`powersave` last, it overrides the rest).
- `platform.lua` is generated from the module's options (monitors, workspaces, xwayland scale, input, gaps and effects,
  keyboard from `00-keyboard.conf`) and base/xdg's default apps for SUPER+a, e and n; per-machine behavior comes from
  there, never a hostname check (`l-dotfiles-platform-facts`).
- Config and dispatch are Lua: `hyprctl dispatch "hl.dsp.exec_cmd('cmd')"`; `hyprctl dispatch exec cmd` fails.
  API stub: `config/hl.meta.lua`.
- `scripts/plugins.nu` builds the plugins per user against the package headers, no hyprpm. `scripts/lid.nu` turns
  the internal panel off while the lid is closed and an external monitor is on. `scripts/reload.nu` is the one
  config-only reload (the reload verb, the plugin loader, toggle-powermode): it replays the monitor-scale and shader
  toggles a reload drops, runs every step even when one fails and then names each failed one.
- The screen share picker is `omarchy-share-picker-git`, built from `mirror/pkgbuilds/` with a patch that lists
  floating windows too.
- `GDK_SCALE` (`xwayland_scale`) reaches GTK only, never `Xft.dpi` (GTK would double its fonts). Every other xwayland
  toolkit gets its own scale: Qt5 xcb `QT_SCALE_FACTOR` (`base/v4l-utils/scripts/qvidcap.sh`, `programming/renderdoc`),
  Tk `tk scaling` (`desktop/applications/scripts/gitk.tcl`, `idle.py`), wine `LogPixels`
  (`desktop/applications/mod.nu`), plain Xft the point size (`desktop/nsxiv`), a pkexec'd root GTK app its own
  `GDK_SCALE` (`desktop/gparted/scripts/gparted-run.sh`), ONLYOFFICE `force-scale` (`desktop/applications/mod.nu`).
- An edit lands with `dot apply desktop/hyprland`, live in Luca's session: a window rule, an `hl.on` handler or a
  keybind that acts on windows passes a nested Hyprland first (`l-dotfiles-gui-testing`, nested.md).
