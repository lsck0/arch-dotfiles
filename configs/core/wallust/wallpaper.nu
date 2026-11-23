use font.nu [font-save]
use palette.nu [condition-derived hex-to-rgb]
use ../../../scripts/lib/state.nu [xdg file-trim]
use ../../../scripts/toggles/lib.nu [quickshell-call]

const INTERNAL = path self ../../../scripts/lib/internal.nu
const LIST = path self wallpaper-list.nu
const PICK = path self wallpaper-pick.nu
const THEMES = path self ../../../themes
const CONFIG = path self wallust.toml
const COLORS_TEMPLATE = path self templates/wal/colors.json
const WAL = "wal"
# what is in effect: a theme's name, or DERIVED for a palette taken from the wallpaper; named for nvim, its first reader
const RECORD = "nvim_theme"
const DERIVED = "pywal"
# wallpaper, palette (a RECORD value), nonce; renamed to TAKEN before applying, so a newer request is a new file
const REQUEST = "theme.request"
const TAKEN = "theme.taken"
const UNIT = "dot-theme.service"
# the last picks, newest first, RECENT_KEPT themes by name and as many wallpapers by path: the picker's side column shows
# three of each beside the one in effect
const RECENT = "theme-recent.json"
const RECENT_KEPT = 4

def wal [...parts: string]: nothing -> path { xdg cache $WAL ...$parts }

def recorded []: nothing -> string { file-trim (wal $RECORD) }

def request-file []: nothing -> path { xdg runtime $REQUEST }

def request-pending []: nothing -> bool { request-file | path exists }

# The newest request, moved aside so the path unit only sees what arrives after it; "" when none waits.
def request-take []: nothing -> string {
    let taken = xdg runtime $TAKEN
    if (do { ^mv -f (request-file) $taken } | complete).exit_code != 0 { return "" }
    file-trim $taken
}

def themes []: nothing -> table<name: string, wallpaper: string> {
    glob ($THEMES | path join "*.json") | sort
    | each {|f| {name: ($f | path parse | get stem), wallpaper: (open $f).wallpaper} }
}

# A pick: a bare theme name is that theme on its wallpaper, anything else a wallpaper under the palette derived from it.
export def pick-resolve [pick: string, themes: table]: nothing -> record<wallpaper: string, palette: string> {
    let theme = $themes | where name == $pick | get --optional 0
    if $theme != null { {wallpaper: $theme.wallpaper, palette: $theme.name} } else { {wallpaper: $pick, palette: $DERIVED} }
}

# The record of the last picks with one more in front: a named palette is a theme pick, a derived one a wallpaper pick.
export def recent-add [recent: record, file: string, palette: string]: nothing -> record {
    let kind = if $palette == $DERIVED { "wallpapers" } else { "themes" }
    let pick = if $palette == $DERIVED { $file } else { $palette }
    $recent | upsert $kind ([$pick] ++ ($recent | get --optional $kind | default [] | where $it != $pick) | first $RECENT_KEPT)
}

def recent-record [file: string, palette: string]: nothing -> nothing {
    let path = xdg state dotfiles $RECENT
    let recent = try { open $path | into record } catch { {} }
    mkdir ($path | path dirname)
    recent-add $recent $file $palette | to json | save --force $path
}

# The palette a wallpaper keeps when nothing new was picked: the recorded one; without a usable record (a fresh home,
# a theme since removed) the theme naming the file, else derived.
export def palette-kept [recorded: string, wallpaper: string, themes: table]: nothing -> string {
    if $recorded == $DERIVED or $recorded in $themes.name { return $recorded }
    $themes | where wallpaper == ($wallpaper | path basename) | get name.0? | default $DERIVED
}

# The theme in effect by name, "pywal" for a derived palette.
export def theme-get []: nothing -> string { palette-kept (recorded) (wallpaper-get) (themes) }

# What wallust derives from a wallpaper, as colors.json's record: the repo's settings with that one template, rendered
# into dir, so nothing live is written before the palette is conditioned.
def derive [file: path, dir: path]: nothing -> record {
    let out = $dir | path join raw.json
    mkdir ($dir | path join templates)
    cp $COLORS_TEMPLATE ($dir | path join templates colors.json)
    open $CONFIG | upsert templates {json: {template: colors.json, target: $out, pywal: true}} | to toml
    | save --force ($dir | path join wallust.toml)
    ^wallust run -s -q -d $dir $file
    open $out
}

# magick's `histogram:info:` lines as colours with their pixel counts.
export def picture-parse []: string -> table<rgb: list<float>, count: int> {
    $in | lines | parse --regex '^\s*(?<count>\d+):.*?#(?<hex>[0-9A-Fa-f]{6})'
    | each { {rgb: ($in.hex | hex-to-rgb), count: ($in.count | into int)} }
}

# The picture's colours for `condition-derived`: its first frame at 64x64, quantized to 16. Empty when magick cannot
# read the file, which leaves the accent as derived.
def picture-colors [file: path]: nothing -> table<rgb: list<float>, count: int> {
    let read = do {
        ^magick -define jpeg:size=128x128 $"($file)[0]" -resize "64x64!" -depth 8 -colors 16 -format "%c" histogram:info:-
    } | complete
    if $read.exit_code == 0 { $read.stdout | picture-parse } else { [] }
}

# The wallpaper's derived palette, conditioned, applied the way a theme is.
def derived-apply [file: path]: nothing -> nothing {
    let dir = mktemp --directory
    let failed = try {
        let scheme = $dir | path join derived.json
        derive $file $dir | condition-derived (picture-colors $file) | to json | save $scheme
        ^wallust cs -s --wallpaper $file $scheme
        null
    } catch {|e| $e.msg }
    rm --recursive $dir
    if $failed != null { error make {msg: $failed} }
}

# False when a newer request arrived. A theme's font applies only when the wallpaper or the palette changes.
def recolor [file: path, palette: string]: nothing -> bool {
    if not ($file | path exists) { error make {msg: $"wallpaper not found: ($file)"} }
    let switched = (wallpaper-get) != ($file | path expand) or (theme-get) != $palette
    ^ln -sfn $file (wal wallpaper)
    $"($file)\n" | save --force (wal wallpaper_path)
    if (which quickshell | is-not-empty) { quickshell-call background set $file | complete | ignore }
    if $palette == $DERIVED { derived-apply $file } else {
        # by path: wallust matches a name as a prefix, gruvbox-dark would also match gruvbox-dark-soft
        let theme = $THEMES | path join $"($palette).json"
        ^wallust cs -s --wallpaper $file $theme
        let font = open $theme | get font? | default ""
        if $switched and $font != "" { font-save {family: $font} }
    }
    $"($palette)\n" | save --force (wal $RECORD)
    not (request-pending)
}

# The unit's body: the newest request, one per run; dot-theme.path starts the next run for a request written meanwhile.
export def theme-serve []: nothing -> nothing {
    let request = request-take
    if $request == "" { return }
    let file = $request | lines | first
    let palette = $request | lines | get 1
    # a failed verb is the theme apply's own report; the run still succeeds, so dot-theme.service keeps a newer request
    try {
        if (recolor $file $palette) { ^nu --no-config-file $INTERNAL theme apply $file }
    } catch {|e| print --stderr $"theme: ($file | path basename): ($e.msg)" }
}

export def wallpaper-get []: nothing -> string {
    try { ^readlink -f (wal wallpaper) | str trim } catch { "" }
}

# Wallpapers fitting the largest monitor in physical pixels, rotation swapping the axes.
export def wallpaper-list []: nothing -> list<string> {
    let screen = try { ^hyprctl monitors -j | from json } catch { [] }
        | each { if $in.transform mod 2 == 1 { [$in.height $in.width] } else { [$in.width $in.height] } }
        | sort-by { $in.0 * $in.1 } | last
    ^$LIST ...(if $screen == null { [] } else { [--screen $"($screen.0)x($screen.1)"] }) | lines
}

# Newest request wins, one switch at a time; before the unit exists (first apply) it runs inline. A pick is recorded
# among the last ones, a rerun of what is in effect is not.
def request [wallpaper: string, palette: string, sync: bool, --pick]: nothing -> nothing {
    let file = if ($wallpaper | str contains "/") { $wallpaper } else {
        let found = do { ^$LIST --resolve $wallpaper } | complete
        if $found.exit_code != 0 { error make {msg: ($found.stderr | str trim)} }
        $found.stdout | str trim
    } | path expand
    if not ($file | path exists) { error make {msg: $"wallpaper not found: ($file)"} }
    if $pick { recent-record $file $palette }
    let request = request-file
    $"($file)\n($palette)\n(random uuid)\n" | save --force $"($request).tmp"
    ^mv -f $"($request).tmp" $request
    if (do { ^systemctl --user cat $UNIT } | complete).exit_code != 0 {
        theme-serve
        return
    }
    # a start joins a running run and returns when it ends
    if not $sync { return }
    loop {
        let started = do { ^systemctl --user start $UNIT } | complete
        if $started.exit_code != 0 {
            error make {msg: $"wallpaper: switching to ($file) failed, journalctl --user -u ($UNIT)"}
        }
        if not (request-pending) { break }
    }
}

# A pick: `dot theme <name>`, the picker's two tabs.
export def theme-set [pick: string, --sync]: nothing -> nothing {
    let to = pick-resolve $pick (themes)
    request --pick $to.wallpaper $to.palette $sync
}

# This wallpaper under what is in effect: every rerun without a new pick (a font change, an apply).
export def wallpaper-set [wallpaper: string, --sync]: nothing -> nothing {
    request $wallpaper (palette-kept (recorded) $wallpaper (themes)) $sync
}

export def wallpaper-random [--sync]: nothing -> nothing {
    let all = wallpaper-list
    if ($all | is-empty) { error make {msg: "no eligible wallpaper"} }
    request --pick ($all | shuffle | first) $DERIVED $sync
}

export def wallpaper-pick []: nothing -> nothing {
    let picked = do { wallpaper-list | str join "\n" | ^$PICK } | complete
    if $picked.exit_code != 0 { error make {msg: ($picked.stderr | str trim | default --empty "no eligible wallpaper")} }
    let file = $picked.stdout | str trim
    if $file == "" {
        print "wallpaper: none picked"
        return
    }
    request --pick $file $DERIVED false
}
