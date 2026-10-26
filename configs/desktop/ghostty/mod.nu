use module.nu *
use ../../core/wallust/palette.nu [OPACITY_SURFACE]
use ../../core/wallust/font.nu [font-load]

export const meta = {deps: [desktop/hyprland], packages: {pacman: [ghostty xdg-terminal-exec]}}

const SERVICE = "app-com.mitchellh.ghostty.service"

export def link [cfg: record] {
    let config = (xdg config)
    let apps = xdg data applications
    let runtime = $env.XDG_RUNTIME_DIR? | default $"/run/user/(^id -u | str trim)"
    let scale = xwayland-scale-for $cfg
    [
        (file-copy config ($config | path join ghostty config))
        (link-commands xdg/ghostty-window.nu)
        (file-render xdg/ghostty-new-window.desktop ($apps | path join ghostty-new-window.desktop) {HOME: $nu.home-dir})
        (file-copy xdg/xdg-terminals.list ($config | path join xdg-terminals.list))
        (file-link ($runtime | path join toggles ghostty-powersave.conf) (xdg cache ghostty-powersave.conf))
        # GDK_SCALE only for what a tab runs, so ghostty's own gtk keeps the compositor's fractional scale
        (file-text ($config | path join dotfiles ghostty-env.conf) $"env = GDK_SCALE=($scale)\n")
        (file-text ($config | path join dotfiles ghostty-style.conf) $"background-opacity = ($OPACITY_SURFACE)\n")
        (dropin $SERVICE systemd/override.conf)
        (dropin app-ghostty-surface-transient-.scope systemd/surface.conf)
        (unit-enable $SERVICE)
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let config = (xdg config)
    let font = font-load
    let fragment = $"font-family = ($font.mono)\nfont-family = Symbols Nerd Font Mono\nfont-size = ($font.size)\n"
    [
        (file-text ($config | path join dotfiles ghostty-font.conf) $fragment --generated)
        (if not (process-running ghostty) { [] } else {
            exec ghostty-reload [
                timeout 5 gdbus call --session --dest com.mitchellh.ghostty --object-path /com/mitchellh/ghostty
                --method org.gtk.Actions.Activate reload-config "[]" "{}"
            ]
        })
    ]
}
