# The pointer: rose-pine's hyprcursor shapes recoloured to the palette, built into one theme that holds both the
# hyprcursor and the xcursor set, rebuilt when the palette changes. The session takes it while active is on;
# otherwise, and before the first build, the stock rose-pine themes stay in effect.

use module.nu *
use ../../core/wallust/scripts/palette.nu [ACCENT_RATIO FOREGROUND_RATIO hex-to-rgb readable-on rgb-to-hex]
use ../hyprland/mod.nu [hyprland-live reload]
export use scripts/size.nu [CURSOR_SIZE_PX cursor-size]

export const meta = {
    packages: {pacman: [librsvg rose-pine-cursor rose-pine-hyprcursor xorg-xcursorgen]}
}

export const options = {
    active: {
        type: bool
        default: true
        doc: "Hyprland, X11, gtk and KDE apps take the palette's cursor; off, they keep the stock rose-pine one"
        label: "Palette cursor"
        scope: user
    }
    size_px: {
        type: int
        default: $CURSOR_SIZE_PX
        doc: "Pointer size in Hyprland, X11, gtk and KDE apps; scaled outputs ask for up to twice it"
        label: "Cursor size"
        min: 16
        max: 128
        scope: user
        apply: relogin
    }
}

const CURSOR_THEME = "palette-cursor"
# the stock xcursor theme: the fallback, the source of every xcursor name an app may ask for, and of the animated
# wait and progress cursors the hyprcursor set lacks
export const STOCK = "BreezeX-RosePine-Linux"

const SELF = path self
const SOURCE_PACKAGE = "rose-pine-hyprcursor"
const SOURCE_DIR = "/usr/share/icons/rose-pine-hyprcursor/hyprcursors"
const STOCK_CURSORS = "/usr/share/icons/BreezeX-RosePine-Linux/cursors"
# 1x, 1.6x and 2x of the size: what scaled outputs and GDK_SCALE ask an X11 app for
const XCURSOR_FACTORS = [1.0 1.6 2.0]
# rose-pine's colours, by the palette role each takes; a badge draws its glyph in the outline colour
const SOURCE_COLORS = {
    body: ["191724"]
    outline: ["e0def4" "f2e9e1"]
    c1: ["eb6f92" "b4637a" "ed1515" "ff0045"]
    c2: ["31748f" "18c087" "11d116"]
    c3: ["f6c177" "ea9d34" "f67400" "f7a61f" "ef6501"]
    c4: ["9ccfd8" "3daee9" "18a0fb" "2eafbb" "2c2f78"]
    c5: ["c4a7e7"]
    c6: ["ebbcba" "d7827e"]
}
const ACCENT_SLOTS = [c1 c2 c3 c4 c5 c6]

def theme-dir []: nothing -> path { xdg data icons $CURSOR_THEME }

def cache-dir []: nothing -> path { xdg cache dotfiles cursor }

# The body on the background, the outline readable on it, each accent readable under the outline-coloured badge
# glyph; rose-pine's own colours before the first palette.
def cursor-colors []: nothing -> record {
    let p = palette-load
    if $p == null { return ($SOURCE_COLORS | update cells { $"#($in.0)" }) }
    let body = $p.bg | hex-to-rgb
    let outline = $p.fg | hex-to-rgb | readable-on $body --ratio $FOREGROUND_RATIO
    $ACCENT_SLOTS | reduce --fold {body: ($body | rgb-to-hex --prefix "#"), outline: ($outline | rgb-to-hex --prefix "#")} {|slot, acc|
        $acc | insert $slot ($p | get $slot | hex-to-rgb | readable-on $outline --ratio $ACCENT_RATIO | rgb-to-hex --prefix "#")
    }
}

def svg-recolor [colors: record]: string -> string {
    let svg = $in
    $SOURCE_COLORS | items {|role, hexes| {role: $role, hexes: $hexes} } | reduce --fold $svg {|r, acc|
        $acc | str replace --all --regex $"\(?i\)#\(($r.hexes | str join '|')\)\\b" ($colors | get $r.role)
    }
}

# The source package's shapes unpacked once per version: <cache>/source/<version>/<shape>/{meta.hl,*.svg}.
def source-extract []: nothing -> path {
    let source = cache-dir | path join source
    let dir = $source | path join (package-version $SOURCE_PACKAGE)
    if ($dir | path exists) { return $dir }
    let next = cache-dir | path join stage-extract
    rm --recursive --force $next
    for hlc in (glob ($SOURCE_DIR | path join "*.hlc")) {
        let shape = $next | path join ($hlc | path parse | get stem)
        mkdir $shape
        ^bsdtar -xf $hlc -C $shape
    }
    rm --recursive --force $source
    mkdir $source
    mv $next $dir
    $dir
}

def meta-read [file: path]: nothing -> record {
    let rows = open --raw $file | lines | parse --regex '^\s*(?<key>\w+)\s*=\s*(?<value>.*?)\s*$'
    let get = {|key| $rows | where key == $key | get value | first }
    {
        hotspot_x: (do $get hotspot_x | into float)
        hotspot_y: (do $get hotspot_y | into float)
        image: (do $get define_size | split row "," | last | str trim)
    }
}

# Every stock xcursor name that is or links to one of the shapes, by that shape.
def stock-names [shapes: list<string>]: nothing -> table<name: string, shape: string> {
    ls --long $STOCK_CURSORS | each {|e|
        let name = $e.name | path basename
        {name: $name, shape: (if $e.type == symlink { $e.target | path basename } else { $name })}
    } | where shape in $shapes
}

# hyprcursor-util's working state, recoloured: <src>/manifest.hl, <src>/hyprcursors/<shape>/{meta.hl,*.svg}.
def shapes-recolor [shapes: path, colors: record, src: path]: nothing -> nothing {
    for shape in (ls $shapes | get name) {
        let dest = $src | path join hyprcursors ($shape | path basename)
        mkdir $dest
        cp ($shape | path join meta.hl) $dest
        for svg in (glob ($shape | path join "*.svg")) {
            open --raw $svg | svg-recolor $colors | save ($dest | path join ($svg | path basename))
        }
    }
    let manifest = [
        $"name = ($CURSOR_THEME)" "description = rose-pine's cursors in the palette's colours" "version = 1"
        "cursors_directory = hyprcursors"
    ]
    $manifest | to text | save ($src | path join manifest.hl)
}

def hyprcursor-build [src: path, out: path]: nothing -> nothing {
    let built = cache-dir | path join stage-hyprcursor
    mkdir $built
    ^hyprcursor-util --create $src -o $built | ignore
    cp --recursive ($built | path join $"theme_($CURSOR_THEME)" "*" | into glob) $out
}

# One xcursor per shape at XCURSOR_FACTORS of size with the hyprcursor hotspots, and a link for every stock name of it.
def xcursor-build [shapes: path, out: path, size: int]: nothing -> nothing {
    let cursors = $out | path join cursors
    let pngs = cache-dir | path join stage-xcursor
    mkdir $cursors $pngs
    let names = ls $shapes | get name | path basename
    $names | par-each {|shape|
        let meta = meta-read ($shapes | path join $shape meta.hl)
        let svg = $shapes | path join $shape $meta.image
        let config = $XCURSOR_FACTORS | each { $in * $size | math round | into int } | each {|size|
            let png = $pngs | path join $"($shape)-($size).png"
            ^rsvg-convert --width $size --height $size $svg --output $png
            let hot = {|f| [($f * $size | math round | into int) ($size - 1)] | math min }
            $"($size) (do $hot $meta.hotspot_x) (do $hot $meta.hotspot_y) ($png)"
        }
        let file = $pngs | path join $"($shape).cfg"
        $config | to text | save $file
        ^xcursorgen $file ($cursors | path join $shape)
    } | ignore
    stock-names $names | where name != $it.shape | each {|a| ^ln -s $a.shape ($cursors | path join $a.name) } | ignore
    ["[Icon Theme]" $"Name=($CURSOR_THEME)" $"Inherits=($STOCK)"] | to text | save ($out | path join index.theme)
}

# Builds the theme beside the live one and swaps it in; active, hands it to a running Hyprland and to the session's
# environment, which X11 apps read at start.
export def build [colors_json: string, active: string, size: string]: nothing -> nothing {
    let shapes = source-extract
    let src = cache-dir | path join stage-source
    let next = cache-dir | path join stage-theme
    let stages = [$src $next (cache-dir | path join stage-hyprcursor) (cache-dir | path join stage-xcursor)]
    rm --recursive --force ...$stages
    mkdir $src $next
    shapes-recolor $shapes ($colors_json | from json) $src
    hyprcursor-build $src $next
    xcursor-build ($src | path join hyprcursors) $next ($size | into int)
    let dest = theme-dir
    mkdir ($dest | path dirname)
    rm --recursive --force $dest
    mv $next $dest
    rm --recursive --force ...$stages
    if $active == "true" and (hyprland-live) {
        ^hyprctl setcursor $CURSOR_THEME $size | ignore
        ^systemctl --user set-environment $"XCURSOR_THEME=($CURSOR_THEME)" $"HYPRCURSOR_THEME=($CURSOR_THEME)"
        # dynamic-cursors' shake magnifier reloads its theme only on a config reload, not on setcursor
        reload
    }
}

# The xcursor theme the session's apps are pointed at.
export def cursor-name [active: bool]: nothing -> string { if $active { $CURSOR_THEME } else { $STOCK } }

# hyprland's environment, from a drop-in that only names a built theme
def hyprland-dropin []: nothing -> string {
    let manifest = theme-dir | path join manifest.hl
    [
        $"local built = io.open\(($manifest | to json)\)"
        "if built then"
        "    built:close()"
        $"    hl.env\(\"HYPRCURSOR_THEME\", ($CURSOR_THEME | to json)\)"
        $"    hl.env\(\"XCURSOR_THEME\", ($CURSOR_THEME | to json)\)"
        "end"
    ] | to text
}

export def hypr-reload []: nothing -> nothing { reload }

export def link [cfg: record] {
    if not $cfg.active { return [] }
    [
        (file-text ($nu.home-dir | path join .config hypr dropins cursor.lua) (hyprland-dropin) --then (then-step hypr-reload))
        # X11 apps started without XCURSOR_THEME take the default theme
        (file-text (xdg data icons default index.theme) $"[Icon Theme]\nInherits=($CURSOR_THEME),($STOCK)\n")
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let colors = cursor-colors
    let active = $cfg.active | into string
    let size = $cfg.size_px | into string
    let key = [(package-version $SOURCE_PACKAGE) ($colors | to nuon) (open --raw $SELF | hash sha256) $active $size] | str join " "
    step build ($colors | to json --raw) $active $size --key $key --undo [rm --recursive --force (theme-dir)]
}
