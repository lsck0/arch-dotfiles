use module.nu *

export const meta = {packages: {pacman: [entr tmux tmux-fingers tmux-sessionizer]}, inputs: [~/.config/tms/config.toml]}

const CONFIG_DIR = ".config/tmux"
const TMS_CONFIG = ".config/tms/config.toml"
const PROJECTS_DEPTH = 1

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $CONFIG_DIR
    let projects = $nu.home-dir | path join projects
    let tms = $nu.home-dir | path join $TMS_CONFIG
    let wanted = {path: $projects, depth: $PROJECTS_DEPTH}
    let searched = if ($tms | path exists) { open $tms | get --optional search_dirs | default [] } else { [] }
    [
        (file-render tmux.conf ($dir | path join tmux.conf) {CACHE: (xdg cache)})
        (file-copy popup.nu ($dir | path join popup.nu) --mode 755)
        (file-copy autoreload.nu ($dir | path join autoreload.nu) --mode 755)
        (if $wanted in $searched { [] } else { step tms-search $projects ($PROJECTS_DEPTH | into string) })
    ]
}

export def tmux-reload []: nothing -> nothing {
    let colors = xdg cache wal colors-tmux.conf
    for s in (glob ($env.TMUX_TMPDIR? | default /tmp | path join $"tmux-(^id -u | str trim)" "*")) {
        try { ^tmux -S $s source-file $colors o+e>| ignore }
    }
}

export def theme [cfg: record, wallpaper: string] {
    step tmux-reload
}

export def tms-search [path: string, depth: string]: nothing -> nothing {
    let wanted = {path: $path, depth: ($depth | into int)}
    let file = $nu.home-dir | path join $TMS_CONFIG
    let config = if ($file | path exists) { open $file } else { {} }
    let dirs = $config.search_dirs? | default [] | where path != $wanted.path | append $wanted
    mkdir ($file | path dirname)
    $config | upsert search_dirs $dirs | to toml | save --force $file
}
