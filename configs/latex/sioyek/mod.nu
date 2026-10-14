use module.nu *

export const meta = {packages: {pacman: [sioyek-git]}}

export def link [cfg: record] {
    [
        (files-into ($nu.home-dir | path join .config sioyek) prefs_user.config keys_user.config)
        # on PATH, invoked bare by tmux/herdr/nvim/viewers
        (link-commands synctex-edit.nu)
    ]
}
