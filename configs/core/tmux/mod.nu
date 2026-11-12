use module.nu *

export const meta = {deps: [core/cli], packages: {pacman: [entr tmux tmux-fingers tmux-sessionizer]}, inputs: [~/.config/tms/config.toml]}

const TMS_CONFIG = "tms/config.toml"
const PROJECTS_DEPTH = 1

export def link [cfg: record] {
    let dir = xdg config tmux
    let projects = $nu.home-dir | path join projects
    let tms = xdg config $TMS_CONFIG
    let wanted = {path: $projects, depth: $PROJECTS_DEPTH}
    let searched = if ($tms | path exists) { open $tms | get --optional search_dirs | default [] } else { [] }
    [
        (file-render tmux.conf ($dir | path join tmux.conf) {CACHE: (xdg cache)})
        ([popup.nu autoreload.nu] | each {|script| file-copy $script ($dir | path join $script) --mode 755 })
        (step tms-search $projects ($PROJECTS_DEPTH | into string) --done=($wanted in $searched))
    ]
}

export def tmux-reload []: nothing -> nothing {
    let colors = xdg cache wal colors-tmux.conf
    # the dir also holds each server's autoreload lock files
    let dir = $env.TMUX_TMPDIR? | default /tmp | path join $"tmux-(^id -u | str trim)"
    let sockets = if ($dir | path exists) { ls $dir | where type == socket | get name } else { [] }
    for s in $sockets {
        try { ^tmux -S $s source-file $colors o+e>| ignore }
    }
}

export def theme [cfg: record, wallpaper: string] {
    step tmux-reload
}

export def tms-search [path: string, depth: string]: nothing -> nothing {
    let wanted = {path: $path, depth: ($depth | into int)}
    let file = xdg config $TMS_CONFIG
    let config = if ($file | path exists) { open $file } else { {} }
    let dirs = $config.search_dirs? | default [] | where path != $wanted.path | append $wanted
    mkdir ($file | path dirname)
    $config | upsert search_dirs $dirs | to toml | save --force $file
}
