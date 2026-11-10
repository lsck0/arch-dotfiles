use module.nu *
use ini.nu [ini-rows]
use ../../core/wallust/palette.nu *
use ../../core/wallust/font.nu [font-load]
use hook/spicetify-apply.nu [apply-pending]

export const meta = {packages: {pacman: [spicetify-cli spotify spotify-player unzip websocat]}}

const THEMES_URL = "https://github.com/spicetify/spicetify-themes.git"
const THEMES_COMMIT = "33a08ea009687f5a42ff678015c28797fe142a7c"

const THEME_INI = "Themes/wal/color.ini"
const THEME_CSS = "Themes/wal/user.css"
const EXTENSIONS = [adblock.js no-music-videos.js]
const SETTINGS = [
    [section key value];
    [Setting current_theme wal] [Setting color_scheme pywal] [AdditionalOptions experimental_features "0"]
    [Setting overwrite_assets "1"] [Preprocesses remove_rtl_rule "0"]
]

def spicetify-dir []: nothing -> path {
    xdg config spicetify
}

export def link [cfg: record] {
    let themes = spicetify-dir | path join Themes
    let base = [
        (fetch-git $THEMES_URL $THEMES_COMMIT $themes)
        # spotify's slider is its stream's channel volume; a restored stream volume under it caps max volume
        (file-copy wireplumber.conf (xdg config wireplumber wireplumber.conf.d spotify.conf))
    ] | decls-flatten
    if (^pacman -Q spotify | complete).exit_code != 0 { return $base }
    let prefs = xdg config spotify prefs
    let configured = configure-done
    [
        $base
        # spicetify's first run reads spotify's prefs; an empty one stands in before spotify's first start
        (exec spotify-prefs [install -D --mode 644 /dev/null $prefs] --creates $prefs)
        (file-copy adblock.js (spicetify-dir | path join Extensions adblock.js))
        (file-copy no-music-videos.js (spicetify-dir | path join Extensions no-music-videos.js))
        (if $configured { [] } else { step configure })
        (desktop-override spotify.desktop {
            $in | str replace --all --regex '(?m)^Exec=spotify ' $"Exec=($env.PWD)/spotify-launch.nu "
        })
        (if $configured and not (apply-pending) { [] } else { exec spicetify-apply [./hook/spicetify-apply.nu] })
        # --permanent also runs it on every login: an upgrade while logged out fires no path unit
        (user-hook spicetify-apply hook/spicetify-apply.nu --permanent --watch [
            "%h/.config/spotify/prefs" "/opt/spotify/Apps/xpui.spa"
        ])
    ]
}

# Whether config-xpui.ini already holds what configure sets, read from the file instead of spicetify.
def configure-done []: nothing -> bool {
    let ini = spicetify-dir | path join config-xpui.ini
    if not ($ini | path exists) { return false }
    let rows = ini-rows (open --raw $ini) | where key != null | select section key value
    let extensions = $rows | where section == AdditionalOptions and key == extensions | get --optional 0.value | default ""
        | split row "|"
    ($SETTINGS | all {|s| $s in $rows }) and ($EXTENSIONS | all { $in in $extensions })
}

export def configure []: nothing -> nothing {
    let settings = $SETTINGS | each {|s| [$s.key $s.value] } | flatten
    # remove_rtl_rule on also strips the [dir=ltr] rules spotify's spacing lives in
    ^spicetify config ...$settings | ignore
    # `config extensions` toggles an entry, so only when absent
    let enabled = ^spicetify config extensions | lines | str trim | where $it != ""
    for ext in $EXTENSIONS {
        if $ext not-in $enabled { ^spicetify config extensions $ext | ignore }
    }
}

export def spicetify-colors []: nothing -> any {
    let slot = wal-load "spotify theme"
    if $slot == null { return null }
    let bg = do $slot background "#0b1019" | condition-bg
    let fg = do $slot foreground "#c2c3c5" | readable-on $bg --ratio 7.0
    let accent = do $slot color4 "#B68B74" | vivify 0.45 0.55 | readable-on $bg --ratio 3.0
    let muted = do $slot color8 "#5a616e" | readable-on $bg --ratio 1.9
    let card = $bg | shade 0.03
    let highlight = $bg | shade 0.075
    let highlight_elevated = $bg | shade 0.11
    [
        [text $fg] [subtext ($fg | dim-toward $bg --ratio 4.6)] [main $bg] [main-elevated ($bg | shade 0.045)]
        [highlight $highlight] [highlight-elevated $highlight_elevated] [sidebar $bg] [player $bg] [card $card]
        [shadow [0.0 0.0 0.0]] [selected-row $fg] [button $accent] [button-active ($accent | lift 0.08)]
        [button-disabled $muted] [tab-active $highlight_elevated] [notification ($accent | selection-pair $fg | first)]
        [notification-error ($accent | semantic error $bg --ratio 3.0)] [misc $muted]
        [card-background $highlight] [card-hover $highlight] [gradienttop $card] [gradientbottom $bg]
    ] | each { {key: $in.0, hex: ($in.1 | rgb-to-hex)} }
}

# user.css with the radius and the font
def user-css []: nothing -> string {
    let font = font-load
    open --raw user.css
    | str replace --regex --multiline '^(\s*--radius:) .*$' $"${1} ($RADIUS_PX)px;"
    | str replace --regex --multiline '^(\s*--font-scale:) .*$' $"${1} ($font.scale);"
    | str replace --regex 'font-family: "[^"]*", "Symbols Nerd Font"' $'font-family: "($font.family)", "Symbols Nerd Font"'
}

export def theme [cfg: record, wallpaper: string] {
    let ini = spicetify-dir | path join $THEME_INI
    let css = spicetify-dir | path join $THEME_CSS
    let colors = spicetify-colors
    if $colors == null or not ($ini | path dirname --num-levels 2 | path exists) { return [] }
    let width = $colors.key | str length | math max
    let body = $colors | each { $"($in.key | fill --width $width) = ($in.hex)\n" } | str join
    [
        (file-text $ini $"[pywal]\n($body)" --generated)
        (file-text $css (user-css) --generated)
        (exec spotify-reload [./spotify-reload.nu])
    ]
}
