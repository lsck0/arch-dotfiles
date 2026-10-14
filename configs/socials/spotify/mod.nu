use module.nu *
use ../../core/wallust/palette.nu *

export const meta = {packages: {pacman: [spicetify-cli spotify spotify-player]}}

const THEMES_URL = "https://github.com/spicetify/spicetify-themes.git"
const THEMES_COMMIT = "33a08ea009687f5a42ff678015c28797fe142a7c"
# obs taps spotify before its loudness lanes, so spotify normalizes itself: -14 lufs, no limiter
const LOUDNESS = {"": {audio.normalize_v2: "true", audio.loudness.environment: "1"}}

const THEME_INI = "Themes/wal/color.ini"

def spicetify-dir []: nothing -> path {
    $nu.home-dir | path join .config spicetify
}

export def link [cfg: record] {
    let themes = spicetify-dir | path join Themes
    let base = [
        (fetch-git $THEMES_URL $THEMES_COMMIT $themes)
        (file-copy user.css ($themes | path join wal user.css))
    ] | decls-flatten
    if (^pacman -Q spotify | complete).exit_code != 0 { return $base }
    let prefs = $nu.home-dir | path join .config spotify prefs
    # spotify rewrites its prefs on exit
    let running = ps | where name == spotify | is-not-empty
    [
        $base
        (if $running { [] } else {
            glob ($nu.home-dir | path join .config spotify Users * prefs) | each {|p| ini-merge $p $LOUDNESS }
        })
        # spicetify's first run generates its config from spotify's prefs; before spotify's first start an empty one
        # stands in (spotify fills it, the hook waits for its autologin line)
        (exec spotify-prefs [touch $prefs] --creates $prefs)
        # blockthespot-style ad and telemetry block
        (file-copy adblock.js (spicetify-dir | path join Extensions adblock.js))
        (step configure)
        (desktop-override spotify.desktop {
            $in | str replace --all --regex '(?m)^Exec=spotify ' $"Exec=($env.PWD)/spotify-launch.nu "
        })
        # spicetify patches a copy of the client in this home: on the first login, every upgrade (a fresh xpui.spa) and
        # every login (an upgrade while logged out fires no path unit)
        (exec spicetify-apply [./hook/spicetify-apply.nu])
        (user-hook spicetify-apply hook/spicetify-apply.nu --permanent --watch [
            "%h/.config/spotify/prefs" "/opt/spotify/Apps/xpui.spa"
        ])
    ]
}

export def configure []: nothing -> nothing {
    ^spicetify config current_theme wal color_scheme pywal experimental_features 0 overwrite_assets 1 | ignore
    # on, it also strips the [dir=ltr] rules spotify's spacing lives in
    ^spicetify config remove_rtl_rule 0 | ignore
    # `config extensions` toggles an entry, so only when absent
    if not (^spicetify config extensions | str trim | split row "|" | any { $in == "adblock.js" }) {
        ^spicetify config extensions adblock.js | ignore
    }
}

# spicetify's colour keys over the conditioned palette, discord's theme takes the same ones
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
        # user.css's own
        [card-background $highlight] [card-hover $highlight] [gradienttop $card] [gradientbottom $bg]
    ] | each { {key: $in.0, hex: ($in.1 | rgb-to-hex)} }
}

# a running spotify keeps playing and picks the theme up on its next start
export def theme [cfg: record, wallpaper: string] {
    let ini = spicetify-dir | path join $THEME_INI
    let colors = spicetify-colors
    if $colors == null or not ($ini | path dirname | path exists) { return [] }
    let width = $colors.key | str length | math max
    let body = $colors | each { $"($in.key | fill --width $width) = ($in.hex)\n" } | str join
    let refresh = if (which spicetify | is-empty) { [] } else { [spicetify -n refresh] }
    file-text $ini $"[pywal]\n($body)" --generated --then $refresh
}
