#!/usr/bin/env -S nu --no-config-file

const PLUGINS = [Bridge Fab]

def main []: nothing -> nothing {
    let engine = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join unreal-engine
    let stamps = $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state) | path join unreal-plugins
    if not ($engine | path exists) { return }
    mkdir $stamps
    for plugin in $PLUGINS {
        let zip = glob ($nu.home-dir | path join sync vendor $"Linux_($plugin)_*.zip") | sort --natural | last
        if $zip == null { continue }
        let stamp = $stamps | path join $plugin
        let current = ($stamp | path exists) and (open --raw $stamp | str trim) == ($zip | path basename)
        if $current and ($engine | path join Engine Plugins $plugin | path exists) { continue }
        print -e $"unreal: installing ($plugin) from ($zip | path basename)"
        ^unzip -oq $zip -d $engine
        $"($zip | path basename)\n" | save --force $stamp
    }
}
