use module.nu *

export const meta = {deps: [core/wallust], packages: {pacman: [yazi]}}

const CONFIG_DIR = ".config/yazi"

export def link [cfg: record] {
    files-into ($nu.home-dir | path join $CONFIG_DIR) yazi.toml keymap.toml
}

export def theme [cfg: record, wallpaper: string] {
    let rendered = $nu.home-dir | path join .cache wal colors-yazi.toml
    if not ($rendered | path exists) { return [] }
    file-text ($nu.home-dir | path join $CONFIG_DIR theme.toml) (open --raw $rendered) --generated
}
