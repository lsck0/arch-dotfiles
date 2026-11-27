use module.nu *
use ini.nu [ini-rows]
use ../../core/wallust/scripts/palette.nu [RADIUS_PX SHADE_CHROME SHADE_CURRENT condition-bg dim-toward lift palette-rgb readable-on rgb-to-hex selection-pair semantic shade vivify]
use ../../core/wallust/scripts/font.nu [font-load]
use scripts/hook/spicetify-apply.nu [apply-pending]

export const meta = {packages: {pacman: [spicetify-cli spotify spotify-player unzip websocat]}}

export const options = {
    adblock: {type: bool, default: true, doc: "Inject spicetify's adblock extension", label: "Adblock", scope: user}
    music_videos_hidden: {type: bool, default: true, doc: "Inject the extension that hides music videos", label: "Hide music videos", scope: user}
}

const THEMES_URL = "https://github.com/spicetify/spicetify-themes.git"
const THEMES_COMMIT = "176fdc7b334c3579475edc3f17452bf87f53d51b" # committed 2026-11-09

const THEME_INI = "Themes/wal/color.ini"
const THEME_CSS = "Themes/wal/user.css"
# the extensions in config/, each behind its option
const EXTENSIONS = {adblock: adblock.js, music_videos_hidden: no-music-videos.js}
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
        (file-copy config/wireplumber.conf (xdg config wireplumber wireplumber.conf.d spotify.conf))
    ]
    if (package-version spotify) == null { return $base }
    let prefs = xdg config spotify prefs
    let extensions = extensions-wanted $cfg
    let configured = configure-done $extensions
    [
        $base
        # spicetify's first run reads spotify's prefs; an empty one stands in before spotify's first start
        (exec spotify-prefs [install -D --mode 644 /dev/null $prefs] --creates $prefs)
        (files-into (spicetify-dir | path join Extensions) ...($extensions | each { $"config/($in)" }))
        (step configure ...$extensions --done=$configured)
        (desktop-exec spotify.desktop spotify --command $"($env.PWD)/scripts/spotify-launch.nu")
        # the uwsm service the entry launches as; the template's drop-in reaches every instance
        (dropin app-Hyprland-spotify@.service services/kill-mixed.conf)
        (exec spicetify-apply [./scripts/hook/spicetify-apply.nu] --done=($configured and not (apply-pending)))
        # --permanent also runs it on every login: an upgrade while logged out fires no path unit
        (user-hook spicetify-apply scripts/hook/spicetify-apply.nu --permanent --watch [
            "%h/.config/spotify/prefs" "/opt/spotify/Apps/xpui.spa"
        ])
    ]
}

def extensions-wanted [cfg: record]: nothing -> list<string> {
    $EXTENSIONS | items {|option, file| if ($cfg | get $option) { $file } } | compact
}

# Whether config-xpui.ini already holds what configure sets, read from the file instead of spicetify.
def configure-done [wanted: list<string>]: nothing -> bool {
    let ini = spicetify-dir | path join config-xpui.ini
    if not ($ini | path exists) { return false }
    let rows = ini-rows (open --raw $ini) | where key != null | select section key value
    let extensions = $rows | where section == AdditionalOptions and key == extensions | get --optional 0.value | default ""
        | split row "|"
    let unwanted = $EXTENSIONS | values | where $it not-in $wanted
    ($SETTINGS | all {|s| $s in $rows }) and ($wanted | all { $in in $extensions }) and ($unwanted | all { $in not-in $extensions })
}

export def configure [...wanted: string]: nothing -> nothing {
    let settings = $SETTINGS | each {|s| [$s.key $s.value] } | flatten
    # remove_rtl_rule on also strips the [dir=ltr] rules spotify's spacing lives in
    ^spicetify config ...$settings | ignore
    # `config extensions` toggles an entry, so only when absent; a trailing - removes one
    let enabled = ^spicetify config extensions | lines | str trim | where $it != ""
    for ext in ($EXTENSIONS | values) {
        if $ext in $wanted and $ext not-in $enabled { ^spicetify config extensions $ext | ignore }
        if $ext not-in $wanted and $ext in $enabled { ^spicetify config extensions $"($ext)-" | ignore }
    }
}

export def spicetify-colors []: nothing -> any {
    let p = palette-rgb "spotify theme"
    if $p == null { return null }
    let bg = $p.bg | condition-bg
    let fg = $p.fg | readable-on $bg --ratio 7.0
    let accent = $p.c4 | vivify 0.45 0.55 | readable-on $bg --ratio 3.0
    let muted = $p.c8 | readable-on $bg --ratio 1.9
    let card = $bg | shade 0.03
    let highlight = $bg | shade 0.075
    let highlight_elevated = $bg | shade $SHADE_CURRENT
    [
        [text $fg] [subtext ($fg | dim-toward $bg --ratio 4.6)] [main $bg] [main-elevated ($bg | shade $SHADE_CHROME)]
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
    open --raw config/user.css
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
        (file-text $ini $"[pywal]\n($body)" --generated --then [./scripts/spotify-reload.nu])
        (file-text $css (user-css) --generated --then [./scripts/spotify-reload.nu])
    ]
}
