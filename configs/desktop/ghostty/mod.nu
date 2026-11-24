use module.nu *
use ../../core/wallust/scripts/palette.nu [opacity-shell]
use ../../core/wallust/scripts/font.nu [font-load]

export const meta = {deps: [desktop/kitty], reads: [desktop/hyprland], packages: {pacman: [ghostty xdg-terminal-exec]}}

export const options = {
    cursor_style: {type: string, default: block, choices: [block bar underline block_hollow], doc: "Text cursor shape", label: "Cursor style", scope: user}
    cursor_blink: {type: bool, default: true, doc: "Text cursor blinks", label: "Cursor blink", scope: user}
    window_columns: {type: int, default: 115, doc: "A new window's width in cells", label: "Window columns", min: 20, max: 500, scope: user}
    window_rows: {type: int, default: 35, doc: "A new window's height in cells", label: "Window rows", min: 5, max: 200, scope: user}
    scroll_multiplier: {type: float, default: 1.5, doc: "Mouse and touchpad scroll distance multiplier", label: "Scroll speed", min: 0.1, max: 10.0, step: 0.1, scope: user}
}

const SERVICE = "app-com.mitchellh.ghostty.service"
const RELOAD = path self scripts/ghostty-reload.sh

export def link [cfg: record] {
    let config = xdg config
    let apps = xdg data applications
    let scale = xwayland-scale-for $cfg
    [
        (file-render config/config ($config | path join ghostty config) {
            CACHE: (xdg cache), CONFIG: $config, CURSOR_STYLE: $cfg.cursor_style, CURSOR_BLINK: $cfg.cursor_blink
            WINDOW_COLUMNS: $cfg.window_columns, WINDOW_ROWS: $cfg.window_rows, SCROLL_MULTIPLIER: $cfg.scroll_multiplier
        } --then [$RELOAD])
        (link-commands scripts/ghostty-window.sh scripts/ghostty-reload.sh)
        (file-render config/ghostty-new-window.desktop ($apps | path join ghostty-new-window.desktop) {HOME: $nu.home-dir})
        (file-copy config/xdg-terminals.list ($config | path join xdg-terminals.list))
        (file-link (xdg runtime toggles ghostty-powersave.conf) (xdg cache ghostty-powersave.conf))
        # GDK_SCALE only for what a tab runs, so ghostty's own gtk keeps the compositor's fractional scale
        (file-text ($config | path join dotfiles ghostty-env.conf) $"env = GDK_SCALE=($scale)\n")
        (dropin $SERVICE services/override.conf)
        (dropin app-ghostty-surface-transient-.scope services/surface.conf)
        (unit-enable $SERVICE)
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let config = xdg config
    let font = font-load
    let fragment = $"font-family = ($font.mono)\nfont-family = Symbols Nerd Font Mono\nfont-size = ($font.size)\n"
    [
        (file-text ($config | path join dotfiles ghostty-font.conf) $fragment --generated)
        (file-text ($config | path join dotfiles ghostty-style.conf) $"background-opacity = (opacity-shell)\n" --generated)
        (if (process-running ghostty) {
            exec ghostty-reload [$RELOAD]
        })
    ]
}
