use module.nu *

export const meta = {packages: {pacman: [sioyek-git]}}

export def link [cfg: record] {
    [
        (file-render prefs_user.config (xdg config sioyek prefs_user.config) {CACHE: (xdg cache)})
        (files-into (xdg config sioyek) keys_user.config)
        (link-commands synctex-edit.nu)
    ]
}
