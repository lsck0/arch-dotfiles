use module.nu *

export const meta = {packages: {pacman: [entr tmux tmux-fingers tmux-sessionizer]}, inputs: [~/.config/tms/config.toml]}

const CONFIG_DIR = ".config/tmux"
const TMS_CONFIG = ".config/tms/config.toml"

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $CONFIG_DIR
    let projects = $nu.home-dir | path join projects
    let tms = $nu.home-dir | path join $TMS_CONFIG
    # tms owns its config (bookmarks land there too), so only a missing search dir is added
    let searched = if ($tms | path exists) { open $tms | get --optional search_dirs.path | default [] } else { [] }
    [
        (file-copy tmux.conf ($dir | path join tmux.conf))
        (file-copy popup.nu ($dir | path join popup.nu) --mode 755)
        (file-copy autoreload.nu ($dir | path join autoreload.nu) --mode 755)
        (if $projects in $searched { [] } else { exec tms-search [tms config -p $projects] })
    ]
}

# every running server (each -L socket) re-sources the colours, no restart; a dead socket is skipped
export def tmux-reload []: nothing -> nothing {
    let colors = $nu.home-dir | path join .cache wal colors-tmux.conf
    for s in (glob ($env.TMUX_TMPDIR? | default /tmp | path join $"tmux-(^id -u | str trim)" "*")) {
        try { ^tmux -S $s source-file $colors o+e>| ignore }
    }
}

export def theme [cfg: record, wallpaper: string] {
    step tmux-reload
}
