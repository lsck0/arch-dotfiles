use module.nu *

export const meta = {packages: {pacman: [libnotify sioyek-git]}}

export def link [cfg: record] {
    [
        (file-render config/prefs_user.config (xdg config sioyek prefs_user.config) {CACHE: (xdg cache)})
        (files-into (xdg config sioyek) config/keys_user.config)
        (link-commands scripts/synctex-edit.nu)
    ]
}
