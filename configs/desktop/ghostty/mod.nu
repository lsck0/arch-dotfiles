use module.nu *
use ../../core/wallust/palette.nu [OPACITY_SURFACE]

export const meta = {deps: [desktop/hyprland], packages: {pacman: [ghostty xdg-terminal-exec]}}

const SERVICE = "app-com.mitchellh.ghostty.service"

export def link [cfg: record] {
    let config = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config)
    let apps = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join applications
    let runtime = $env.XDG_RUNTIME_DIR? | default $"/run/user/(^id -u | str trim)"
    let scale = xwayland-scale-for $cfg
    [
        # a link: toggle-font rewrites the repo file
        (file-link config ($config | path join ghostty config))
        (link-commands xdg/ghostty-window.nu)
        (file-render xdg/ghostty-new-window.desktop ($apps | path join ghostty-new-window.desktop) {HOME: $nu.home-dir})
        (file-copy xdg/xdg-terminals.list ($config | path join xdg-terminals.list))
        (file-link ($runtime | path join toggles ghostty-powersave.conf) ($nu.home-dir | path join .cache ghostty-powersave.conf))
        # GDK_SCALE only for what a tab runs, so ghostty's own gtk keeps the compositor's fractional scale
        (file-text ($config | path join dotfiles ghostty-env.conf) $"env = GDK_SCALE=($scale)\n")
        (file-text ($config | path join dotfiles ghostty-style.conf) $"background-opacity = ($OPACITY_SURFACE)\n")
        (dropin $SERVICE systemd/override.conf)
        (dropin app-ghostty-surface-transient-.scope systemd/surface.conf)
        (unit-enable $SERVICE)
    ]
}

export def theme [cfg: record, wallpaper: string] {
    if (^pgrep -x ghostty | complete).exit_code != 0 { return [] }
    exec ghostty-reload [
        timeout 5 gdbus call --session --dest com.mitchellh.ghostty --object-path /com/mitchellh/ghostty
        --method org.gtk.Actions.Activate reload-config "[]" "{}"
    ]
}
