use module.nu *
use ini.nu [ini-apply ini-rows]
use ../../core/wallust/palette.nu [ICON_THEMES hex-to-rgb readable-on rgb-to-hex semantic shade]
use ../../core/wallust/font.nu [font-load]

export const meta = {
    deps: [core/locale]
    packages: {
        pacman: [
            ark bluedevil dolphin kdeplasma-addons kscreen plasma-desktop plasma-integration plasma-nm plasma-pa plasma-vault
            polkit-kde-agent spectacle
        ]
    }
}

export const options = {
    kwin_outputs: {
        type: bool?
        default: null
        doc: "Ship the committed kwin output layout; detected: on when a connected monitor's EDID is one it describes"
        label: "KWin output layout"
    }
    locale: {
        type: bool
        default: true
        doc: "Ship plasma-localerc with core/locale's language"
        label: "Plasma locale"
    }
}

const DIR = path self .
const CONFIG = ".config"
const TEMPLATES = [plasma-org.kde.plasma.desktop-appletsrc plasmarc kscreenlockerrc]
const OUTPUTS = "kwinoutputconfig.json"
const LOCALERC = "plasma-localerc"
const THEMED = ["kdeglobals" "color-schemes/pywal.colors"]
const CONFIG_DIRS = [KDE kdedefaults plasma-workspace]
const APPLETSRC = "plasma-org.kde.plasma.desktop-appletsrc"
const KICKOFF_FAVORITES = "favoritesPortedToKAstats=true"
const KACTIVITIES_DB = ".local/share/kactivitymanagerd/resources/database"
const DOLPHIN_STATE = ".local/state/dolphinstaterc"
const DOLPHIN_VIEW = "dolphin/view_properties/global/.directory"
const WAL_WALLPAPER = "wal/wallpaper"
const WALLPAPER_SECTION = '^\[(?<s>Containments\]\[\d+\]\[Wallpaper\]\[org\.kde\.image\]\[General)\]$'
const DRM = "/sys/class/drm"
const MODERNCLOCK = {id: com.github.prayag2.modernclock, url: "https://github.com/prayag2/kde_modernclock", commit: 5c86f0f23d2646be7e9872fc5e769bdce259af92}
const KDE_FONT_KEYS = [
    [group key];
    [General font] [General fixed] [General menuFont] [General smallestReadableFont] [General toolBarFont] [WM activeFont]
]
const KDE_SMALLEST_OFFSET = 2
# Button, header and alternate-row surfaces stepped off the conditioned bg, as oomox steps its gtk ones.
const KDE_SURFACE_SHADES = {alt: 0.03, header: 0.045, button: 0.075}
const KDE_INACTIVE_RATIO = 3.0
# Runtime state KDE rewrites on its own; dropped from the backup so the repo does not churn on it.
const VOLATILE_KEYS = [
    [file section key];
    ["KDE/UserFeedback.conf" UserFeedback LastEncouragement]
    [kded6rc PlasmaBrowserIntegration shownCount]
    [plasmashellrc Updates performed]
]

def config-path [name: string]: nothing -> path {
    $nu.home-dir | path join $CONFIG $name
}

def rc-files []: nothing -> list<string> {
    glob ($DIR | path join "*rc") | path basename
    | where $it not-in ($TEMPLATES ++ $THEMED ++ [$LOCALERC])
}

export def detect [cfg: record]: nothing -> record {
    let ours = open ($DIR | path join $OUTPUTS) | where name == outputs | get 0.data.edidHash
    # the connectors are links, which glob does not follow
    let connected = ls $DRM | get name | each { path join edid } | where ($it | path exists) | each { open --raw $in | hash md5 }
    {kwin_outputs: ($connected | any { $in in $ours })}
}

def wallpaper-values [applets: string, wallpaper: string]: nothing -> record {
    let image = {Image: $"file://($wallpaper)"}
    $applets | lines | parse --regex $WALLPAPER_SECTION | get s | reduce --fold {} {|s, acc| $acc | insert $s $image }
}

# The wallpaper the last theme switch applied, "" before the first.
def wallpaper-current []: nothing -> string {
    let link = xdg cache $WAL_WALLPAPER
    if ($link | path exists) { $link | path expand } else { "" }
}

# Seeds dolphin's view properties only: dolphin rewrites them on every view change.
def dolphin-view [dest: path]: nothing -> list<record> {
    let values = ini-rows (open --raw $DOLPHIN_VIEW) | where key != null
        | reduce --fold {} {|r, acc| $acc | upsert $r.section {|v| $v | get --optional $r.section | default {} | insert $r.key $r.value } }
    if ($values | is-empty) { [] } else { [(ini-merge $dest $values --missing-only)] }
}

export def link [cfg: record] {
    let config = $nu.home-dir | path join $CONFIG
    let values = {HOME: $nu.home-dir, DOTFILES: $env.DOTFILES}
    # kickoff ports its favorites into the activity database only while this is false; a fresh account has none yet
    let fresh = not ($nu.home-dir | path join $KACTIVITIES_DB | path exists)
    # rendered in too, else every apply would take back what theme set
    let wallpaper = wallpaper-current
    let lang = $cfg.deps?."core/locale"?.lang?
    let applets = file-render (host-seed $DIR $APPLETSRC) ($config | path join $APPLETSRC) $values
        | update content { if $fresh { str replace $KICKOFF_FAVORITES "favoritesPortedToKAstats=false" } else { $in } }
        | update content {|d| if $wallpaper == "" { $d.content } else { $d.content | ini-apply (wallpaper-values $d.content $wallpaper) false } }
    let dirs = $CONFIG_DIRS | each {|d| glob ($DIR | path join $d "**/*") --no-dir } | flatten
        | each {|f| file-copy $f ($config | path join ($f | path relative-to $DIR)) }
    [
        (files-into (xdg data applications) ...(glob ($DIR | path join applications "*.desktop")))
        (dolphin-view (xdg data $DOLPHIN_VIEW))
        (files-into (xdg data dbus-1 services) dbus/org.kde.KSplash.service)
        # no kiosk key hides dolphin's dock short of shell_access=false, which also stops it running any executable
        (ini-merge ($nu.home-dir | path join $DOLPHIN_STATE) {State: {State: (open --raw dolphin/dock-state | str trim)}})
        (rc-files | each {|f| file-copy $f ($config | path join $f) })
        (if $cfg.locale and $lang != null { file-render $LOCALERC ($config | path join $LOCALERC) {LANG: $lang} } else { [] })
        $applets
        (file-render plasmarc ($config | path join plasmarc) $values)
        (file-render kscreenlockerrc ($config | path join kscreenlockerrc) $values)
        (if $cfg.kwin_outputs == true { file-copy $OUTPUTS ($config | path join $OUTPUTS) } else { [] })
        $dirs
        (if (xdg data plasma plasmoids $MODERNCLOCK.id | path exists) { [] } else {
            let src = xdg cache dotfiles modernclock
            (fetch-git $MODERNCLOCK.url $MODERNCLOCK.commit $src) ++ [(exec $"install ($MODERNCLOCK.id)" [kpackagetool6 -t Plasma/Applet -i ($src | path join package)])]
        })
    ]
}

def rgb [hex: string]: nothing -> string {
    $hex | str trim --left --char "#" | split chars | chunks 2 | each { str join | into int --radix 16 } | str join ","
}

# c6/c5 links nearly vanish on the selection accent, so readable-on walks them toward black or white.
def selection [p: record]: nothing -> list<string> {
    let accent = $p.c4 | hex-to-rgb
    [$p.bg $p.c6 $p.c5] | each { hex-to-rgb | readable-on $accent | rgb-to-hex --prefix "#" }
}

def kde-colors [p: record]: nothing -> record {
    let accent = rgb $p.c4
    let sel = selection $p | each { rgb $in }
    let sel_inactive = rgb ($p.fg | hex-to-rgb | readable-on ($p.c4 | hex-to-rgb) --ratio $KDE_INACTIVE_RATIO | rgb-to-hex)
    let hex = {|color| rgb ($color | rgb-to-hex) }
    let bg = $p.bg_conditioned | hex-to-rgb
    let surface = $KDE_SURFACE_SHADES | items {|name, amount| {$name: ($bg | shade $amount)} }
        | reduce --fold {base: $bg} {|it, acc| $acc | merge $it }
    let text = {|on|
        # semantic's hue walk is bounded, so readable-on holds the status colors to the text ratio
        let status = {|role| do $hex ($p.c4 | hex-to-rgb | semantic $role $on | readable-on $on) }
        {
            fg: (do $hex ($p.fg | hex-to-rgb | readable-on $on))
            inactive: (do $hex ($p.c8 | hex-to-rgb | readable-on $on --ratio $KDE_INACTIVE_RATIO))
            link: (do $hex ($p.c6 | hex-to-rgb | readable-on $on))
            visited: (do $hex ($p.c5 | hex-to-rgb | readable-on $on))
            negative: (do $status error)
            neutral: (do $status warn)
            positive: (do $status ok)
        }
    }
    let set = {|bg, alt, fg, active, t|
        {
            BackgroundNormal: $bg BackgroundAlternate: $alt ForegroundNormal: $fg ForegroundInactive: $t.inactive
            ForegroundActive: $active DecorationFocus: $accent DecorationHover: $accent ForegroundLink: $t.link
            ForegroundVisited: $t.visited ForegroundNegative: $t.negative ForegroundNeutral: $t.neutral
            ForegroundPositive: $t.positive
        }
    }
    let on = {|bg, alt, title|
        let t = do $text $bg
        do $set (do $hex $bg) (do $hex $alt) ($t | get $title) $accent $t
    }
    let sel_text = do $text ($p.c4 | hex-to-rgb) | merge {inactive: $sel_inactive, link: $sel.1, visited: $sel.2}
    let plain = do $on $surface.base $surface.alt fg
    let title = do $text $surface.base
    let title_inactive = do $text $surface.alt
    {
        "Colors:Window": $plain
        "Colors:View": $plain
        "Colors:Button": (do $on $surface.button $surface.alt fg)
        "Colors:Tooltip": $plain
        "Colors:Header": (do $on $surface.header $surface.base fg)
        "Colors:Header][Inactive": (do $on $surface.header $surface.base inactive)
        "Colors:Complementary": $plain
        "Colors:Selection": (do $set $accent $accent $sel.0 $sel.0 $sel_text)
        WM: {
            activeBackground: (do $hex $surface.base) activeBlend: (do $hex $surface.base) activeForeground: $title.fg
            inactiveBackground: (do $hex $surface.alt) inactiveBlend: (do $hex $surface.alt) inactiveForeground: $title_inactive.inactive
        }
        General: {ColorScheme: pywal, AccentColor: $accent}
    }
}

def wallpaper-set [wallpaper: string]: nothing -> list<record> {
    let applets = config-path $APPLETSRC
    if $wallpaper == "" or not ($applets | path exists) { return [] }
    let running = process-running plasmashell
    [
        (ini-merge $applets (wallpaper-values (open --raw $applets) $wallpaper))
        (if $running { exec plasma-wallpaper [plasma-apply-wallpaperimage $wallpaper] } else { [] })
    ]
}

# The qt font strings' family and size over the template's: the font beside the palette (core/wallust/font.nu).
def kde-fonts [template: string]: nothing -> record {
    let font = font-load
    let size = $font.ui_size
    let current = $template | lines
    $KDE_FONT_KEYS | reduce --fold {} {|k, acc|
        let line = $current | where ($it | str starts-with $"($k.key)=") | get --optional 0
        if $line == null { return $acc }
        let fields = $line | str replace $"($k.key)=" "" | split row ","
        let pt = if $k.key == smallestReadableFont { $size - $KDE_SMALLEST_OFFSET } else { $size }
        let family = if $k.key == fixed { $font.mono } else { $font.family }
        $acc | upsert $k.group {|r| $r | get --optional $k.group | default {} | insert $k.key ($fields | update 0 $family | update 1 ($pt | into string) | str join ",") }
    }
}

def kde-icons [p: record]: nothing -> record {
    {Icons: {Theme: (if $p.light == "1" { $ICON_THEMES.light } else { $ICON_THEMES.dark })}}
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    let colors = if $p == null { null } else { kde-colors $p }
    let themed = $THEMED | each {|f|
        let dest = if $f == "kdeglobals" { config-path $f } else { xdg data $f }
        if $colors == null { return (file-copy $f $dest) }
        let colors = if $f == "kdeglobals" {
            $colors | merge deep (kde-fonts (open --raw $f)) | merge deep (kde-icons $p)
        } else {
            $colors | upsert General.Name pywal
        }
        file-text $dest (open --raw $f | ini-apply $colors false) --generated
    }
    # running KDE apps (dolphin's daemon) keep their palette until told, and widgets built later inherit it
    let notify = if $colors == null or ($env.DBUS_SESSION_BUS_ADDRESS? | is-empty) { [] } else {
        [(exec kde-palette [dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0])]
    }
    $themed ++ $notify ++ (wallpaper-set $wallpaper)
}

def themed-keys []: nothing -> list<string> {
    let grey = [bg fg c4 c5 c6 c8 bg_conditioned] | reduce --fold {} {|slot, acc| $acc | insert $slot "#808080" }
    let colors = kde-colors $grey | items {|section, keys| $keys | columns | each {|k| $"($section)/($k)" } } | flatten
    $colors ++ ($KDE_FONT_KEYS | each { $"($in.group)/($in.key)" }) ++ ["General/ColorSchemeHash" "Icons/Theme"]
}

# Themed keys as the module has them, so only a real settings edit reaches the backup.
def kdeglobals-back [live: string, template: string]: nothing -> string {
    let themed = themed-keys
    let own = {|r| $r.key != null and $"($r.section)/($r.key)" in $themed }
    let kept = ini-rows $template | where {|r| do $own $r }
    ini-rows $live | each {|r|
        if not (do $own $r) { return $r.line }
        $kept | where section == $r.section and key == $r.key | get --optional 0.line
    } | compact | str join "\n" | $"($in)\n"
}

# Drops the VOLATILE_KEYS lines from the backed-up copies so KDE's own runtime churn stays out of the repo.
def strip-volatile []: nothing -> nothing {
    for v in $VOLATILE_KEYS {
        let dest = $DIR | path join $v.file
        if not ($dest | path exists) { continue }
        ini-rows (open --raw $dest) | where {|r| not ($r.section == $v.section and $r.key == $v.key) }
        | get line | str join "\n" | $"($in)\n" | save --force $dest
    }
}

export def backup [cfg: record]: nothing -> nothing {
    let files = rc-files | append (if $cfg.kwin_outputs == true { [$OUTPUTS] } else { [] })
    for f in $files {
        if (config-path $f | path exists) { cp --force (config-path $f) ($DIR | path join $f) }
    }
    let globals = config-path $THEMED.0
    if ($globals | path exists) {
        kdeglobals-back (open --raw $globals) (open --raw ($DIR | path join $THEMED.0)) | save --force ($DIR | path join $THEMED.0)
    }
    for f in $TEMPLATES {
        if not (config-path $f | path exists) { continue }
        let dest = if $f == $APPLETSRC { host-file $DIR $f } else { $DIR | path join $f }
        mkdir ($dest | path dirname)
        open --raw (config-path $f) | str replace --all $env.DOTFILES "@DOTFILES@" | str replace --all $nu.home-dir "@HOME@"
        | str replace "favoritesPortedToKAstats=false" $KICKOFF_FAVORITES | save --force $dest
    }
    for d in $CONFIG_DIRS {
        if not (config-path $d | path exists) { continue }
        rm --recursive --force ($DIR | path join $d)
        cp --recursive (config-path $d) ($DIR | path join $d)
    }
    strip-volatile
}
