use module.nu *

export const meta = {deps: [desktop/hyprland], packages: {pacman: [ghostty xdg-terminal-exec]}}

const SERVICE = "app-com.mitchellh.ghostty.service"

export def link [cfg: record] {
    let config = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config)
    let apps = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join applications
    let runtime = $env.XDG_RUNTIME_DIR? | default $"/run/user/(^id -u | str trim)"
    let scale = $cfg.deps?."desktop/hyprland"?.xwayland_scale? | default (display-xwayland-scale ($env.FORM_FACTOR? | default ""))
    [
        # a link: toggle-font rewrites the repo file
        (file-link config ($config | path join ghostty config))
        # Terminal=true entries: xdg-terminal-exec opens a window of the resident instance, not a fresh process
        (link-commands xdg/ghostty-window.nu)
        (file-render xdg/ghostty-new-window.desktop ($apps | path join ghostty-new-window.desktop) {HOME: $nu.home-dir})
        (file-copy xdg/xdg-terminals.list ($config | path join xdg-terminals.list))
        # volatile like tlp's forced mode, so a reboot never leaves power-saver tweaks behind
        (file-link ($runtime | path join toggles ghostty-powersave.conf) ($nu.home-dir | path join .cache ghostty-powersave.conf))
        # xwayland's GDK_SCALE reaches launched apps, not this resident instance's shells; env only goes to what a tab
        # runs, so ghostty's own gtk keeps the compositor's fractional scale
        (file-text ($config | path join dotfiles ghostty-env.conf) $"env = GDK_SCALE=($scale)\n")
        (dropin $SERVICE systemd/override.conf)
        # a prefix drop-in, so every app-ghostty-surface-transient-<pid>.scope picks it up
        (dropin app-ghostty-surface-transient-.scope systemd/surface.conf)
        # prewarm at login, windows open over d-bus via ghostty +new-window
        (unit-enable $SERVICE)
    ]
}

# ghostty has no config watcher; reload_config is only reachable over d-bus
export def theme [cfg: record, wallpaper: string] {
    if (ps | where name == ghostty | is-empty) { return [] }
    exec ghostty-reload [
        timeout 5 gdbus call --session --dest com.mitchellh.ghostty --object-path /com/mitchellh/ghostty
        --method org.gtk.Actions.Activate reload-config "[]" "{}"
    ]
}
