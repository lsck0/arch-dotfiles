#!/usr/bin/env -S nu --no-config-file
# Pastes the clipboard into the window that has focus once the clipboard panel closed: ctrl+shift+v in a terminal,
# ctrl+v anywhere else.

# the panel's layer gives the keyboard back to the window under it after it unmaps
const FOCUS_SETTLE = 150ms
const TERMINAL_CLASSES = [com.mitchellh.ghostty kitty]

def main []: nothing -> nothing {
    sleep $FOCUS_SETTLE
    let class = try { ^hyprctl -j activewindow | from json | get class? } catch { null }
    if $class == null { return }
    if $class in $TERMINAL_CLASSES {
        ^wtype -M ctrl -M shift v -m shift -m ctrl
    } else {
        ^wtype -M ctrl v -m ctrl
    }
}
