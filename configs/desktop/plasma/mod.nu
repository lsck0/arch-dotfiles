# plasma's rc files and applet layout, rendered from templates per machine; theme writes the wallpaper's colors and
# fonts into kdeglobals, backup carries live settings edits back without them

use module.nu *
use ini.nu [ini-apply ini-rows]
use ../../core/wallust/palette.nu [hex-to-rgb readable-on rgb-to-hex]

export const meta = {
    packages: {
        pacman: [
            bluedevil dolphin kdeplasma-addons kscreen plasma-desktop plasma-integration plasma-nm plasma-pa plasma-vault
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
        scope: machine
    }
}

const DIR = path self .
const CONFIG = ".config"
const TEMPLATES = [plasma-org.kde.plasma.desktop-appletsrc plasmarc kscreenlockerrc]
const OUTPUTS = "kwinoutputconfig.json"
const THEMED = ["kdeglobals" "color-schemes/pywal.colors"]
const CONFIG_DIRS = [KDE kdedefaults plasma-workspace]
const APPLETSRC = "plasma-org.kde.plasma.desktop-appletsrc"
const KICKOFF_FAVORITES = "favoritesPortedToKAstats=true"
const KACTIVITIES_DB = ".local/share/kactivitymanagerd/resources/database"
const DOLPHIN_STATE = ".local/state/dolphinstaterc"
const DOLPHIN_VIEW = "dolphin/view_properties/global/.directory"
const WAL_WALLPAPER = ".cache/wal/wallpaper"
const WALLPAPER_SECTION = '^\[(?<s>Containments\]\[\d+\]\[Wallpaper\]\[org\.kde\.image\]\[General)\]$'
const DRM = "/sys/class/drm"
const MODERNCLOCK = {id: com.github.prayag2.modernclock, url: "https://github.com/prayag2/kde_modernclock", commit: 5c86f0f23d2646be7e9872fc5e769bdce259af92}
const KDE_FONT_KEYS = [
    [group key];
    [General font] [General fixed] [General menuFont] [General smallestReadableFont] [General toolBarFont] [WM activeFont]
]
const KDE_SMALLEST_OFFSET = 2
const STATUS_COLORS = {ForegroundNegative: "218,68,83", ForegroundNeutral: "246,116,0", ForegroundPositive: "39,174,96"}

def config-path [name: string]: nothing -> path {
    $nu.home-dir | path join $CONFIG $name
}

def rc-files []: nothing -> list<string> {
    glob ($DIR | path join "*rc") | append ($DIR | path join kdeglobals) | path basename
    | where $it not-in ($TEMPLATES ++ $THEMED)
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
    let link = $nu.home-dir | path join $WAL_WALLPAPER
    if ($link | path exists) { $link | path expand } else { "" }
}

# Seeds dolphin's view properties only: dolphin rewrites them on every view change.
def dolphin-view [dest: path]: nothing -> list<record> {
    let values = ini-rows (open --raw $DOLPHIN_VIEW) | where key != null
        | reduce --fold {} {|r, acc| $acc | upsert $r.section {|v| $v | get --optional $r.section | default {} | insert $r.key $r.value } }
    if ($values | is-empty) { [] } else { [(ini-merge $dest $values --missing-only)] }
}

# Options at their default take the detected values, until dot runs detect itself (modules.nu VERBS lacks it).
def detected [cfg: record]: nothing -> record {
    if $cfg.kwin_outputs == null { $cfg | merge (detect $cfg) } else { $cfg }
}

export def link [cfg: record] {
    let cfg = detected $cfg
    let config = $nu.home-dir | path join $CONFIG
    let values = {HOME: $nu.home-dir, DOTFILES: $env.DOTFILES}
    # kickoff ports its favorites into the activity database only while this is false; a fresh account has none yet
    let fresh = not ($nu.home-dir | path join $KACTIVITIES_DB | path exists)
    # rendered in too, else every apply would take back what theme set
    let wallpaper = wallpaper-current
    let applets = file-render (host-seed $DIR $APPLETSRC) ($config | path join $APPLETSRC) $values
        | update content { if $fresh { str replace $KICKOFF_FAVORITES "favoritesPortedToKAstats=false" } else { $in } }
        | update content {|d| if $wallpaper == "" { $d.content } else { $d.content | ini-apply (wallpaper-values $d.content $wallpaper) false } }
    let dirs = $CONFIG_DIRS | each {|d| glob ($DIR | path join $d "**/*") --no-dir } | flatten
        | each {|f| file-copy $f ($config | path join ($f | path relative-to $DIR)) }
    [
        (files-into ($nu.home-dir | path join .local share applications) ...(glob ($DIR | path join applications "*.desktop")))
        (dolphin-view ($nu.home-dir | path join .local share $DOLPHIN_VIEW))
        (files-into ($nu.home-dir | path join .local share dbus-1 services) dbus/org.kde.KSplash.service)
        # no kiosk key hides dolphin's dock short of shell_access=false, which also stops it running any executable
        (ini-merge ($nu.home-dir | path join $DOLPHIN_STATE) {State: {State: (open --raw dolphin/dock-state | str trim)}})
        (rc-files | where {|f| $f != plasma-localerc or (profile-has secrets) } | each {|f| file-copy $f ($config | path join $f) })
        $applets
        (file-render plasmarc ($config | path join plasmarc) $values)
        (file-render kscreenlockerrc ($config | path join kscreenlockerrc) $values)
        (if $cfg.kwin_outputs == true { file-copy $OUTPUTS ($config | path join $OUTPUTS) } else { [] })
        $dirs
        (if ($nu.home-dir | path join .local share plasma plasmoids $MODERNCLOCK.id | path exists) { [] } else {
            let src = $nu.home-dir | path join .cache dotfiles modernclock
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
    let c = [bg fg c0 c4 c5 c6 c8] | reduce --fold {} {|slot, acc| $acc | insert $slot (rgb ($p | get $slot)) }
    let sel = selection $p | each { rgb $in }
    let set = {|bg, alt, fg, inactive, link, visited|
        {
            BackgroundNormal: $bg BackgroundAlternate: $alt ForegroundNormal: $fg ForegroundInactive: $inactive
            ForegroundActive: $c.c4 DecorationFocus: $c.c4 DecorationHover: $c.c4 ForegroundLink: $link
            ForegroundVisited: $visited
        } | merge $STATUS_COLORS
    }
    {
        "Colors:Window": (do $set $c.bg $c.c0 $c.fg $c.c8 $c.c6 $c.c5)
        "Colors:View": (do $set $c.bg $c.c0 $c.fg $c.c8 $c.c6 $c.c5)
        "Colors:Button": (do $set $c.c0 $c.c8 $c.fg $c.c8 $c.c6 $c.c5)
        "Colors:Tooltip": (do $set $c.bg $c.c0 $c.fg $c.c8 $c.c6 $c.c5)
        "Colors:Header": (do $set $c.c0 $c.bg $c.fg $c.c8 $c.c6 $c.c5)
        "Colors:Header][Inactive": (do $set $c.c0 $c.bg $c.c8 $c.c8 $c.c6 $c.c5)
        "Colors:Complementary": (do $set $c.bg $c.c0 $c.fg $c.c8 $c.c6 $c.c5)
        "Colors:Selection": (do $set $c.c4 $c.c4 $sel.0 $c.fg $sel.1 $sel.2)
        WM: {
            activeBackground: $c.bg activeBlend: $c.bg activeForeground: $c.fg
            inactiveBackground: $c.c0 inactiveBlend: $c.c0 inactiveForeground: $c.c8
        }
        General: {ColorScheme: pywal, AccentColor: $c.c4}
    }
}

def wallpaper-set [wallpaper: string]: nothing -> list<record> {
    let applets = config-path $APPLETSRC
    if $wallpaper == "" or not ($applets | path exists) { return [] }
    let running = (^pgrep -x plasmashell | complete).exit_code == 0
    [
        (ini-merge $applets (wallpaper-values (open --raw $applets) $wallpaper))
        (if $running { exec plasma-wallpaper [plasma-apply-wallpaperimage $wallpaper] } else { [] })
    ]
}

# The qt font strings' family and size over the template's, so a switch keeps what toggle-font set.
def kde-fonts [template: string]: nothing -> record {
    let toggle = $env.DOTFILES | path join scripts toggles toggle-font.nu
    let family = ^$toggle get | complete | get stdout | str trim
    let size = ^$toggle ui-size | complete | get stdout | str trim
    if ($family | is-empty) or $size !~ '^[0-9]+$' { return {} }
    let size = $size | into int
    let current = $template | lines
    $KDE_FONT_KEYS | reduce --fold {} {|k, acc|
        let line = $current | where ($it | str starts-with $"($k.key)=") | get --optional 0
        if $line == null { return $acc }
        let fields = $line | str replace $"($k.key)=" "" | split row ","
        let pt = if $k.key == smallestReadableFont { $size - $KDE_SMALLEST_OFFSET } else { $size }
        $acc | upsert $k.group {|r| $r | get --optional $k.group | default {} | insert $k.key ($fields | update 0 $family | update 1 ($pt | into string) | str join ",") }
    }
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    let colors = if $p == null { null } else { kde-colors $p }
    let themed = $THEMED | each {|f|
        let dest = if $f == "kdeglobals" { config-path $f } else { $nu.home-dir | path join .local share $f }
        if $colors == null { return (file-copy $f $dest) }
        let colors = if $f == "kdeglobals" { $colors | merge deep (kde-fonts (open --raw $f)) } else { $colors | upsert General.Name pywal }
        file-text $dest (open --raw $f | ini-apply $colors false) --generated
    }
    $themed ++ (wallpaper-set $wallpaper)
}

def themed-keys []: nothing -> list<string> {
    let grey = [bg fg c0 c4 c5 c6 c8] | reduce --fold {} {|slot, acc| $acc | insert $slot "#808080" }
    let colors = kde-colors $grey | items {|section, keys| $keys | columns | each {|k| $"($section)/($k)" } } | flatten
    $colors ++ ($KDE_FONT_KEYS | each { $"($in.group)/($in.key)" }) ++ ["General/ColorSchemeHash"]
}

# The live kdeglobals with the themed keys as the module has them: those are wallpaper output, so only a real
# settings edit reaches the backup.
def kdeglobals-back [live: string, template: string]: nothing -> string {
    let themed = themed-keys
    let own = {|r| $r.key != null and $"($r.section)/($r.key)" in $themed }
    let kept = ini-rows $template | where {|r| do $own $r }
    ini-rows $live | each {|r|
        if not (do $own $r) { return $r.line }
        $kept | where section == $r.section and key == $r.key | get --optional 0.line
    } | compact | str join "\n" | $"($in)\n"
}

export def backup [cfg: record]: nothing -> nothing {
    let cfg = detected $cfg
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
}
