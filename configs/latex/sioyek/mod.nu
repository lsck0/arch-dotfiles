use module.nu *

export const meta = {packages: {pacman: [libnotify sioyek-git]}}

export const options = {
    new_window: {type: bool, default: true, doc: "Open each file in its own window", label: "New window per file", scope: user}
    page_separator_px: {type: int, default: 8, doc: "Gap between pages", label: "Page gap (px)", min: 0, max: 64, scope: user}
}

export def link [cfg: record] {
    [
        (file-render config/prefs_user.config (xdg config sioyek prefs_user.config) {
            CACHE: (xdg cache), NEW_WINDOW: (if $cfg.new_window { 1 } else { 0 }), PAGE_SEPARATOR_PX: $cfg.page_separator_px
        })
        (files-into (xdg config sioyek) config/keys_user.config)
        (link-commands scripts/synctex-edit.nu)
    ]
}
