#!/usr/bin/env bash

# qrenderdoc refuses the wayland qt platform ("Wayland Qt platform not supported", it cannot capture or replay a
# wayland window), and QT_QPA_PLATFORM=wayland;xcb lets it pick wayland first; pin xcb so it runs under xwayland
desktop_override renderdoc.desktop 's|^Exec=qrenderdoc |Exec=env QT_QPA_PLATFORM=xcb qrenderdoc |'
