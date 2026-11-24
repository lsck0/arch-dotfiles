use module.nu *

export const meta = {packages: {pacman: [uwsm ksshaskpass breeze5 plasma5-integration plasma-integration]}}

export def link [cfg: record] {
    let dir = xdg config uwsm
    [
        (file-render config/env ($dir | path join env) {DOTFILES: $env.DOTFILES})
        (files-into $dir config/env-hyprland)
    ]
}
