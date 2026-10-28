use module.nu *
use ../../core/wallust/font.nu [font-load]

export const meta = {packages: {pacman: [konsole]}}

const DATA_DIR = ".local/share/konsole"

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $DATA_DIR
    [
        (file-link (xdg cache wal colors-konsole.colorscheme) ($dir | path join pywal.colorscheme))
        (ini-merge (xdg config konsolerc) {"Desktop Entry": {DefaultProfile: "pywal.profile"}})
    ]
}

# pywal.profile carries the theme font, so the theme verb renders it; an apply reruns every linked module's theme verb
export def theme [cfg: record, wallpaper: string] {
    let font = font-load
    let dest = $nu.home-dir | path join $DATA_DIR pywal.profile
    [(file-render pywal.profile $dest {FONT: $font.family, UI_SIZE: $font.ui_size} | file-text $dest $in.content --generated)]
}
