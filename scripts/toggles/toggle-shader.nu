#!/usr/bin/env -S nu --no-config-file
# Each .frag carries @label/@variants/@animated/@themed headers; any shader costs direct scanout.

use lib.nu [status-record status-print notify state-get state-set quickshell-call]

const DAMAGE_FULL = 2
const DAMAGE_NONE = 0

def shader-dir []: nothing -> path { $nu.home-dir | path join .config hypr shaders }
def render-dir []: nothing -> path { $env.XDG_RUNTIME_DIR | path join shaders }
def instance []: nothing -> string { $env.HYPRLAND_INSTANCE_SIGNATURE? | default "" }

def shaders []: nothing -> table {
    glob (shader-dir | path join *.frag) | sort | each {|file|
        let meta = open --raw $file | lines | parse --regex '^// @(?<key>\w+) ?(?<value>.*)$'
        {
            name: ($file | path parse | get stem)
            label: ($meta | where key == label | get value.0? | default "")
            variants: ($meta | where key == variants | get value.0? | default "" | split row " " | compact --empty)
            animated: ("animated" in $meta.key)
            themed: ("themed" in $meta.key)
        }
    }
}

def entries [shaders: table]: nothing -> list<string> {
    $shaders | each {|s| if ($s.variants | is-empty) { [$s.name] } else { $s.variants | each { $"($s.name):($in)" } } }
        | flatten
}

def entry-parse [entry: string, shaders: table]: nothing -> string {
    let first = $shaders | where name == $entry | get variants.0?.0?
    let entry = if $first == null { $entry } else { $"($entry):($first)" }
    if $entry not-in (entries $shaders) {
        error make {msg: $"unknown shader '($entry)', see: toggle-shader.nu list"}
    }
    $entry
}

def current []: nothing -> string {
    let path = ^hyprctl getoption decoration:screen_shader -j | from json | get str
    if $path in ["" "[[EMPTY]]"] {
        "off"
    } else if ($path | path dirname) == (render-dir) and ($path ends-with ".frag") {
        $path | path parse | get stem | str replace "@" ":"
    } else {
        "custom"
    }
}

def entry-label [entry: string, shaders: table]: nothing -> string {
    let parts = $entry | split row ":"
    let label = $shaders | where name == $parts.0 | get label.0
    if ($parts | length) == 1 { $label } else { $"($label): ($parts.1 | str capitalize)" }
}

def theme-constants []: nothing -> record {
    try {
        let palette = quickshell-call shell palette | from json
        let numbers = $palette.background ++ $palette.accent ++ [$palette.glowStrength $palette.scanlineOpacity $palette.scanlineSpacing]
        if not ($numbers | all { ($in | describe) in [int float] }) { error make {msg: "palette is not numeric"} }
        let float = {|x| $x | into string | if $in =~ '[.e]' { $in } else { $"($in).0" } }
        let vec3 = {|v| $"vec3\(($v | each {|c| do $float $c } | str join ', ')\)" }
        {
            "const vec3 BACKGROUND": $"const vec3 BACKGROUND = (do $vec3 $palette.background);"
            "const vec3 ACCENT": $"const vec3 ACCENT = (do $vec3 $palette.accent);"
            "const float GLOW": $"const float GLOW = (do $float $palette.glowStrength);"
            "const float SCANLINE_OPACITY": $"const float SCANLINE_OPACITY = (do $float $palette.scanlineOpacity);"
            "const float SCANLINE_SPACING_PX": $"const float SCANLINE_SPACING_PX = (do $float $palette.scanlineSpacing);"
        }
    } catch { {} }
}

def render [entry: string, shader: record]: nothing -> path {
    let variant = $entry | split row ":" | get 1?
    let constants = if $shader.themed { theme-constants } else { {} }
        | merge (if $variant == null { {} } else {
            {"const int VARIANT": $"const int VARIANT = ($shader.variants | enumerate | where item == $variant | get index.0);"}
        })
    let text = open --raw (shader-dir | path join $"($shader.name).frag") | lines | each {|line|
        let include = $line | parse --regex '^#include "(?<file>[^"]+)"$' | get file.0?
        if $include != null { return (open --raw (shader-dir | path join $include) | lines) }
        let declaration = $line | parse --regex '^(?<decl>const \w+ \w+) = ' | get decl.0?
        $constants | get --optional ($declaration | default "") | default $line
    } | flatten | str join "\n"
    mkdir (render-dir)
    let out = render-dir | path join $"($entry | str replace ':' '@').frag"
    $"($text)\n" | save --force $"($out).tmp"
    mv --force $"($out).tmp" $out
    $out
}

def load [damage: int, shader: string]: nothing -> nothing {
    ^hyprctl eval 'hl.config({ decoration = { screen_shader = "" } })' o> /dev/null
    ^hyprctl eval $"hl.config\({ debug = { damage_tracking = ($damage) } }\)" o> /dev/null
    ^hyprctl eval $"hl.config\({ decoration = { screen_shader = [[($shader)]] } }\)" o> /dev/null
}

def entry-load [entry: string, shaders: table]: nothing -> nothing {
    let shader = $shaders | where name == ($entry | split row ":" | first) | first
    load (if $shader.animated { $DAMAGE_NONE } else { $DAMAGE_FULL }) (render $entry $shader)
}

def apply [entry: string, shaders: table]: nothing -> nothing {
    if $entry == off {
        load $DAMAGE_FULL ""
        state-set shader off --volatile
        notify Shader Off
        return
    }
    entry-load $entry $shaders
    state-set shader $"(instance) ($entry)" --volatile
    state-set shader-last $entry
    notify Shader (entry-label $entry $shaders)
}

def "main get" [--json] {
    let entry = current
    if not $json { return $entry }
    let shaders = shaders
    let text = match $entry { off => "Off", custom => "Custom", _ => (entry-label $entry $shaders) }
    status-print (status-record Shader $entry --text $text --states ([off] | append (entries $shaders))) true
}
def "main list" [] { print (entries (shaders) | str join "\n") }
def "main status" [] { {current: (current), shaders: (shaders | select name label variants)} | to json --raw }

def "main off" [] { apply off (shaders) }

def "main reapply" [] {
    let saved = state-get shader --volatile | split row " "
    if $saved.0 != (instance) or ($saved | length) < 2 or (state-get powersaver --volatile) == on {
        return
    }
    let shaders = shaders
    let entry = try { entry-parse $saved.1 $shaders }
    if $entry != null { entry-load $entry $shaders }
}

# on goes off, off brings back the last shader used
def "main toggle" [] {
    let shaders = shaders
    if (current) != off { return (apply off $shaders) }
    apply (try { entry-parse (state-get shader-last) $shaders } catch { entries $shaders | first }) $shaders
}

def "main set" [entry: string] { let shaders = shaders; apply (entry-parse $entry $shaders) $shaders }

# a bare entry, so `get` output round-trips back through set
def main [entry?: string] { if $entry == null { main toggle } else { main set $entry } }
