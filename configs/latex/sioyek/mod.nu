use module.nu *

export const meta = {packages: {pacman: [sioyek-git]}}

export def link [cfg: record] {
    [
        (files-into (xdg config sioyek) prefs_user.config keys_user.config)
        (link-commands synctex-edit.nu)
    ]
}
