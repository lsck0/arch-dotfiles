use module.nu *

export const meta = {packages: {pacman: [uwsm ksshaskpass plasma5-integration]}}

export def link [cfg: record] {
    let dir = $nu.home-dir | path join .config uwsm
    [
        (file-render env ($dir | path join env) {DOTFILES: $env.DOTFILES})
        (files-into $dir env-hyprland)
    ]
}
