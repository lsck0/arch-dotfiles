use module.nu *
use ../../core/wallust/palette.nu [wal-load condition-bg vivify shade selection-pair readable-on is-light rgb-to-hex]

export const meta = {packages: {pacman: [themix-gui-git themix-plugin-base16-git xorg-server-xvfb]}}

const EXPORT_DIR = ".config/oomox/export_config"
const EXPORT_CONFIGS = [multi_export_oomox_classic.json multi_export_oodwaita.json]
const COLORS = ".cache/wal/colors-oomox"
# themix-multi-export can hang forever on an oomox gtk-loop bug sigterm cannot reap, so timeout kills it after this
const THEMIX_TIMEOUT = [timeout -k 5 20]

export def link [cfg: record] {
    files-into ($nu.home-dir | path join $EXPORT_DIR) ...$EXPORT_CONFIGS
}

export def theme [cfg: record, wallpaper: string] {
    let slot = wal-load "oomox theme"
    if $slot == null { return [] }
    let bg = do $slot background "#0b1019" | condition-bg
    let fg = do $slot foreground "#c2c3c5"
    let accent = do $slot color4 "#B68B74" | vivify 0.45 0.55
    let surfaces = {MENU: ($bg | shade 0.045), TXT: ($bg | shade 0.02), BTN: ($bg | shade 0.075), HDR_BTN: ($bg | shade 0.03)}
    let selection = $accent | selection-pair $fg
    let values = {NAME: wal, BG: ($bg | rgb-to-hex), FG: ($fg | readable-on $bg | rgb-to-hex)}
        | merge ($surfaces | items {|name, c| {$"($name)_BG": ($c | rgb-to-hex), $"($name)_FG": ($fg | readable-on $c | rgb-to-hex)} } | reduce {|it, acc| $acc | merge $it })
        | merge {SEL_BG: ($selection.0 | rgb-to-hex), SEL_FG: ($selection.1 | rgb-to-hex)}
        | merge {GTK3_GENERATE_DARK: (if ($bg | is-light) { "False" } else { "True" }), ROUNDNESS: 3, SPACING: 3, GRADIENT: "0.0"}
    let order = [NAME BG FG MENU_BG MENU_FG SEL_BG SEL_FG TXT_BG TXT_FG BTN_BG BTN_FG HDR_BTN_BG HDR_BTN_FG GTK3_GENERATE_DARK ROUNDNESS SPACING GRADIENT]
    let text = $order | each {|k| $"($k)=($values | get $k)" } | str join "\n"
    [
        (file-text ($nu.home-dir | path join $COLORS) $"($text)\n" --generated)
        (step themix-export)
    ]
}

# themix cannot init gtk without a display and a fresh install's first apply runs headless, so without the theme the
# first login's gtk dialogs (keyring prompt) would come up in plain adwaita
export def themix-export []: nothing -> nothing {
    let headless = ($env.WAYLAND_DISPLAY? | is-empty) and ($env.DISPLAY? | is-empty) and (which xvfb-run | is-not-empty)
    let themix = (if $headless { [xvfb-run -a] } else { [] }) ++ [themix-multi-export]
    let argv = $THEMIX_TIMEOUT ++ $themix
    for config in $EXPORT_CONFIGS {
        # themix reports a missing layout file on every run, so its output only matters when it fails
        let out = ^($argv | first) ...($argv | skip 1) ($nu.home-dir | path join $EXPORT_DIR $config) ($nu.home-dir | path join $COLORS) o+e>| complete
        if $out.exit_code != 0 { error make {msg: $"themix export ($config) exited ($out.exit_code): ($out.stdout | lines | last 3 | str join ' ')"} }
    }
}
