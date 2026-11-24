use module.nu *

export const meta = {deps: [core/wallust], packages: {pacman: [yazi]}}

export const options = {
    show_hidden: {
        type: bool
        default: false
        doc: "Show dotfiles"
        label: "Show hidden files"
        scope: user
    }
    sort_by: {
        type: string
        default: alphabetical
        doc: "File order in a directory"
        label: "Sort by"
        choices: [none mtime btime extension alphabetical natural size random]
        scope: user
    }
}

export def link [cfg: record] {
    let dir = xdg config yazi
    [
        (file-render config/yazi.toml ($dir | path join yazi.toml) {SORT_BY: $cfg.sort_by, SHOW_HIDDEN: $cfg.show_hidden})
        (files-into $dir config/keymap.toml)
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let rendered = xdg cache wal colors-yazi.toml
    if not ($rendered | path exists) { return [] }
    file-text (xdg config yazi theme.toml) (open --raw $rendered) --generated
}
