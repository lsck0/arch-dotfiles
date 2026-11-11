#!/usr/bin/env -S nu --no-config-file
# amdgpu syncs the pipes of outputs with the same timing; powering them off together left one tied to a master already
# off ("syncd with disabled master pipe"), and that screen stayed dark on wake. One output at a time, the first
# listed off last and on first.

def main [mode: string]: nothing -> nothing {
    if $mode not-in [on off] { error make {msg: $"dpms: mode is on or off, not ($mode)"} }
    let names = ^hyprctl monitors all -j | from json | where not disabled | get name
    let order = if $mode == off { $names | reverse } else { $names }
    for name in $order {
        ^hyprctl dispatch $"hl.dsp.dpms\({ mode = '($mode)', monitor = '($name)' }\)" | ignore
        sleep 200ms
    }
}
