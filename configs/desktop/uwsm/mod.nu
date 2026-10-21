use module.nu *

# QT_QPA_PLATFORMTHEME=kde (env) loads KDEPlasmaPlatformTheme: plasma-integration ships qt6's, plasma5-integration
# qt5's, without which qt5 apps fall back to a light fusion
export const meta = {packages: {pacman: [uwsm ksshaskpass plasma5-integration]}}

export def link [cfg: record] {
    let dir = $nu.home-dir | path join .config uwsm
    [
        (file-render env ($dir | path join env) {DOTFILES: $env.DOTFILES})
        (files-into $dir env-hyprland)
    ]
}
