# TODO

## quickshell DE build

The working task list is `configs/quickshell/research/ROADMAP.md` — 14
dependency-ordered phases, plus Appendix A's permanent gotchas (which have
each already cost debugging time at least once). This is just the index.

- [◐] **Phase 8** — wallpaper: `get|list|set` CLI, awww dropped, palette
  transition animated, native image picker wired, three entry points
  consolidated into `Super+W`. Still open: confirming `watch-monitors.sh`
  is redundant (needs a real hotplug to test).
- [◐] **Phase 11** — OSD follows the focused monitor; real mouse-wheel
  delivery to Workspaces verified. Hot-plug and per-monitor widget sets
  still need a second display to test against.
- [◐] **Phase 12** — night light toggle, focus mode, and screenshot
  annotation (`plugins/annotate/Annotate.qml` + `scripts/screenshot-annotate.sh`,
  bound to `Super+Shift+S`/`Super+Shift+Print`/`Ctrl+Shift+Alt+S`) are done.
  `plugins/overview/Overview.qml` covers the workspace switcher as a plain
  QML grid (titles per workspace); still open: live window thumbnails
  (needs `wlr-screencopy` per window), bar auto-hide/reveal, per-app
  notification rules, bluetooth device battery (needs native
  `Quickshell.Bluetooth` bindings).

## Known issues

- [ ] **`wallust run` panics on some photos** — confirmed reproducing on
  `wallpapers/mountain2.jpg` and `wallpapers/road.jpg` (wallust
  4.0.0-alpha): `thread 'main' panicked at src/histogram/salience.rs:124:22:
index out of bounds: the len is 5 but the index is 5`. Only hits the
  **Wallpapers** tab of the image picker (mode 0, raw photo →
  auto-extracted palette via `wallust run`); the **Themes** tab is
  unaffected since it applies a hand-authored palette via `wallust cs`
  instead. Picking one of these two photos directly leaves the palette
  silently unchanged. Not yet reported upstream or worked around.
