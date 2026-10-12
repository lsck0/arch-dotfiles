#!/usr/bin/env bash

# TeamSpeak 6 is a CEF (Chromium) app. Launched by its stock desktop entry it lands on XWayland and renders at 1x, so
# the whole UI is tiny on the 4K desktop. Shadow Exec with --ozone-platform-hint=auto: that makes CEF a native Wayland
# client, so Hyprland drives the scale like every other app here (no per-machine factor, so laptop and desktop both
# just work) and the window gets server-side-free decorations. force-device-scale-factor=$(java_ui_scale) is the
# XWayland fallback and is deliberately left off, as it would wrongly re-scale the native Wayland surface.
# Theme needs nothing: TS6 ships a dark palette as its built-in default (empty current_theme in its own settings.db,
# base CSS --ts-primary-background #333947) and has no prefers-color-scheme switch, so it is dark regardless of the
# portal. The owner can pick another theme under Settings > Appearance.
desktop_override teamspeak6-client.desktop \
    's|^Exec=teamspeak6 |Exec=teamspeak6 --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations |'
