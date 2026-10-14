use module.nu *

export const meta = {packages: {pacman: [uwsm ksshaskpass]}}

export def link [cfg: record] {
    let dir = $nu.home-dir | path join .config uwsm
    [
        (file-render env ($dir | path join env) {DOTFILES: $env.DOTFILES})
        (files-into $dir env-hyprland)
    ]
}
