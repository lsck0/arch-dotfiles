#!/usr/bin/env -S nu --no-config-file
# every translucent quickshell surface is blurred by hyprland_windowrules.lua's quickshell-blur rule: one missing from
# its namespace list (settings was) shows the windows behind it unblurred through a 0.92 fill

const HERE = path self | path dirname
const RULES = path self | path dirname | path join ../hyprland/hyprland_windowrules.lua
# full-screen or invisible layers, never blurred
const UNBLURRED = [background desktop-widgets notification-image-grab]

def main [] {
    let pattern = open --raw $RULES | parse --regex 'name = "quickshell-blur",\s*match = \{\s*namespace = "(?<re>[^"]+)"' | get 0.re
    let qml = glob ($HERE | path join "**/*.qml")
    let cards = $qml | each { open --raw $in | parse --regex '(?m)^\s*name: "(?<n>[a-z-]+)"' | get n } | flatten
    let layers = $qml | each { open --raw $in | parse --regex 'WlrLayershell\.namespace: "quickshell-(?<n>[a-z-]+)"' | get n } | flatten
    let missing = $cards ++ $layers | uniq | where $it not-in $UNBLURRED and $it != "panel-"
        | where {|n| not ($"quickshell-($n)" =~ $pattern) }
    if ($missing | is-not-empty) {
        error make {msg: $"not in the quickshell-blur layer rule: ($missing | str join ', ')"}
    }
}
