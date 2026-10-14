use module.nu *

export const meta = {packages: {pacman: [kitty]}}

# a link: toggle-font rewrites the repo file and kitty rereads it on SIGUSR1
export def link [cfg: record] {
    file-link kitty.conf ($nu.home-dir | path join .config kitty kitty.conf)
}

# kitty reloads its config, which includes the wal colors, on SIGUSR1
export def theme [cfg: record, wallpaper: string] {
    if (ps | where name == kitty | is-empty) { return [] }
    exec kitty-reload [pkill -USR1 -x kitty]
}
