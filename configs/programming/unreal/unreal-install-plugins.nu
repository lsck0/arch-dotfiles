#!/usr/bin/env -S nu --no-config-file

const REPO = path self | path expand | path dirname --num-levels 4
use ($REPO | path join scripts lib state.nu) [file-trim xdg]

const PLUGINS = [Bridge Fab]

def main []: nothing -> nothing {
    let engine = xdg data unreal-engine
    let stamps = xdg state unreal-plugins
    if not ($engine | path exists) { return }
    mkdir $stamps
    for plugin in $PLUGINS {
        let zip = glob ($nu.home-dir | path join sync vendor $"Linux_($plugin)_*.zip") | sort --natural | last
        if $zip == null { continue }
        let stamp = $stamps | path join $plugin
        if (file-trim $stamp) == ($zip | path basename) and ($engine | path join Engine Plugins $plugin | path exists) { continue }
        print -e $"unreal: installing ($plugin) from ($zip | path basename)"
        ^unzip -oq $zip -d $engine
        $"($zip | path basename)\n" | save --force $stamp
    }
}
