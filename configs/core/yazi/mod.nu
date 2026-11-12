use module.nu *

export const meta = {deps: [core/wallust], packages: {pacman: [yazi]}}

export def link [cfg: record] {
    files-into (xdg config yazi) yazi.toml keymap.toml
}

export def theme [cfg: record, wallpaper: string] {
    let rendered = xdg cache wal colors-yazi.toml
    if not ($rendered | path exists) { return [] }
    file-text (xdg config yazi theme.toml) (open --raw $rendered) --generated
}
