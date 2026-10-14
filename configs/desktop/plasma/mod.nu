use module.nu *
use ini.nu [ini-apply]
use ../../core/wallust/palette.nu [hex-to-rgb readable-on rgb-to-hex]

export const meta = {
    packages: {
        pacman: [
            bluedevil dolphin kdeplasma-addons kscreen plasma-desktop plasma-integration plasma-nm plasma-pa plasma-vault
            polkit-kde-agent
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
# plasma's machine state: applet positions per resolution and the screen mapping, rendered, carried back by backup
const TEMPLATES = [plasma-org.kde.plasma.desktop-appletsrc plasmarc]
const OUTPUTS = "kwinoutputconfig.json"
# both written by the theme verb from the palette
const THEMED = ["kdeglobals" "color-schemes/pywal.colors"]
const CONFIG_DIRS = [KDE kdedefaults plasma-workspace]
const APPLETSRC = "plasma-org.kde.plasma.desktop-appletsrc"
const KICKOFF_FAVORITES = "favoritesPortedToKAstats=true"
const KACTIVITIES_DB = ".local/share/kactivitymanagerd/resources/database"
const DOLPHIN_STATE = ".local/state/dolphinstaterc"
const DRM = "/sys/class/drm"
const MODERNCLOCK = {id: com.github.prayag2.modernclock, url: "https://github.com/prayag2/kde_modernclock", commit: 5c86f0f23d2646be7e9872fc5e769bdce259af92}
# fixed on purpose, not from the palette
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

# until dot runs detect itself (modules.nu VERBS lacks it)
def detected [cfg: record]: nothing -> record {
    if $cfg.kwin_outputs == null { $cfg | merge (detect $cfg) } else { $cfg }
}

export def link [cfg: record] {
    let cfg = detected $cfg
    let config = $nu.home-dir | path join $CONFIG
    let values = {HOME: $nu.home-dir, DOTFILES: $env.DOTFILES}
    # kickoff ports its favorites into the activity database only while this is false; a fresh account has none yet
    let fresh = not ($nu.home-dir | path join $KACTIVITIES_DB | path exists)
    let applets = file-render $APPLETSRC ($config | path join $APPLETSRC) $values
        | update content { if $fresh { str replace $KICKOFF_FAVORITES "favoritesPortedToKAstats=false" } else { $in } }
    let dirs = $CONFIG_DIRS | each {|d| glob ($DIR | path join $d "**/*") --no-dir } | flatten
        | each {|f| file-copy $f ($config | path join ($f | path relative-to $DIR)) }
    [
        (files-into ($nu.home-dir | path join .local share applications) ...(glob ($DIR | path join applications "*.desktop")))
        (files-into ($nu.home-dir | path join .local share dolphin view_properties global) dolphin/view_properties/global/.directory)
        # no kiosk key hides dolphin's dock short of shell_access=false, which also stops it running any executable
        (ini-merge ($nu.home-dir | path join $DOLPHIN_STATE) {State: {State: (open --raw dolphin/dock-state | str trim)}})
        # someone else's formats follow the locale bootstrap.sh set, not luca's
        (rc-files | where {|f| $f != plasma-localerc or (profile-has identity) } | each {|f| file-copy $f ($config | path join $f) })
        $applets
        (file-render plasmarc ($config | path join plasmarc) $values)
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

# c6/c5 links nearly vanish on the selection accent: readable-on walks them toward black or white
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
    # one containment per screen and activity
    let sections = open --raw $applets | lines | parse --regex '^\[(?<s>Containments\]\[\d+\]\[Wallpaper\]\[org\.kde\.image\]\[General)\]$' | get s
    let image = {Image: $"file://($wallpaper)"}
    let running = ps | where name == plasmashell | is-not-empty
    [
        (ini-merge $applets ($sections | reduce --fold {} {|s, acc| $acc | insert $s $image }))
        (if $running { exec plasma-wallpaper [plasma-apply-wallpaperimage $wallpaper] } else { [] })
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    let colors = if $p == null { null } else { kde-colors $p }
    let themed = $THEMED | each {|f|
        let dest = if $f == "kdeglobals" { config-path $f } else { $nu.home-dir | path join .local share $f }
        if $colors == null { return (file-copy $f $dest) }
        let colors = if $f == "kdeglobals" { $colors } else { $colors | upsert General.Name pywal }
        file-text $dest (open --raw $f | ini-apply $colors false) --generated
    }
    $themed ++ (wallpaper-set $wallpaper)
}

# the live state back into the module: the rc files and dirs as they are, the templates with their placeholders
export def backup [cfg: record]: nothing -> nothing {
    let cfg = detected $cfg
    let files = rc-files | append $THEMED.0 | append (if $cfg.kwin_outputs == true { [$OUTPUTS] } else { [] })
    for f in $files {
        if (config-path $f | path exists) { cp --force (config-path $f) ($DIR | path join $f) }
    }
    for f in $TEMPLATES {
        if not (config-path $f | path exists) { continue }
        open --raw (config-path $f) | str replace --all $env.DOTFILES "@DOTFILES@" | str replace --all $nu.home-dir "@HOME@"
        | str replace "favoritesPortedToKAstats=false" $KICKOFF_FAVORITES | save --force ($DIR | path join $f)
    }
    for d in $CONFIG_DIRS {
        if not (config-path $d | path exists) { continue }
        rm --recursive --force ($DIR | path join $d)
        cp --recursive (config-path $d) ($DIR | path join $d)
    }
}
