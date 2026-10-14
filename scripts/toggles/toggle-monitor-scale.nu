#!/usr/bin/env -S nu --no-config-file
# monitor scale and layout. `set` applies a scale live and persists it as the machine's desktop/hyprland.monitors
# option; `live` and `layout` are runtime only, a reload restores the option and `reapply` puts them back
use lib.nu [notify state-set state-file]

const DOT = path self ../dot.nu
const HYPRLAND = "desktop/hyprland"
# `toggle`, the menu's enter, cycles the label's monitor through these as the font toggle cycles its shortlist
const SCALES = ["1" "1.25" "1.5" "2"]
const SCALE_TOLERANCE = 0.01
# long enough for hyprland to settle a fractional scale before it is read back
const SCALE_SETTLE = 400ms
# hyprctl prints refreshRate as %.5f, and the mode string keeps that form
const REFRESH_DECIMALS = 5

def instance []: nothing -> string { $env.HYPRLAND_INSTANCE_SIGNATURE? | default "" }

# every output, disabled ones included
def monitors []: nothing -> table { ^hyprctl -j monitors all | from json }

def monitor-find [name: string]: nothing -> any { monitors | where name == $name | get 0? }

def monitor-default []: nothing -> string { ^hyprctl -j monitors | from json | get name.0 }

def scale-get [name: string]: nothing -> string { monitor-find $name | get scale | into string }

def mode-of [monitor: record]: nothing -> string {
    $"($monitor.width)x($monitor.height)@($monitor.refreshRate | into string --decimals $REFRESH_DECIMALS)"
}

# the monitors the option resolves to, detected ones included
def monitors-persisted []: nothing -> list<record> {
    ^$DOT options $HYPRLAND --json | from json | get modules.0.options | where key == monitors | get 0.value | default []
}

# a field of the output's persisted entry, fallback without one
def persisted-get [name: string, key: string, fallback: string]: nothing -> string {
    monitors-persisted | where output == $name | get --optional 0 | get --optional $key | default $fallback | into string
}

# the option's relink rewrites the config, and hyprland's reload step puts the runtime layout and shader back
def persisted-scale-set [name: string, scale: string]: nothing -> nothing {
    let monitors = monitors-persisted
    let current = monitor-find $name
    let entry = $monitors | where output == $name | get --optional 0
        | default {output: $name, mode: (mode-of $current), position: $"($current.x)x($current.y)"}
    let updated = $monitors | where output != $name | append ($entry | upsert scale ($scale | into float)) | sort-by output
    ^$DOT set --machine $"($HYPRLAND).monitors" ($updated | to json --raw)
}

# replayed by `reapply`; keyed to the compositor instance so a new session never inherits it
def record [name: string, kind: string, expr: string]: nothing -> nothing {
    state-set $"monitor-($name)-($kind)" $"(instance) ($expr)" --volatile
}

# a reload resets every output to the file; layouts first, a later live scale merges onto them
def reapply []: nothing -> nothing {
    for kind in [layout scale] {
        for file in (glob (state-file $"monitor-*-($kind)" --volatile)) {
            let saved = open --raw $file | split row --number 2 " "
            if $saved.0 == (instance) { ^hyprctl eval $saved.1 o> /dev/null }
        }
    }
}

# hl.monitor({ key = value, ... }): strings quoted, numbers and bools bare
def lua-monitor [fields: record]: nothing -> string {
    let body = $fields | items {|key, value|
        $"($key) = (if ($value | describe) == string { $'"($value)"' } else { $value | into string })"
    }
    $"hl.monitor\({ ($body | str join ', ') }\)"
}

# live, keeping mode and position
def scale-apply [name: string, scale: string]: nothing -> nothing {
    let monitor = monitor-find $name
    if $monitor == null { error make {msg: $"unknown monitor: ($name)"} }
    let position = $"($monitor.x)x($monitor.y)"
    let expr = lua-monitor {output: $name, mode: (mode-of $monitor), position: $position, scale: ($scale | into float)}
    let reply = ^hyprctl eval $expr | complete
    if $reply.stdout !~ ok { error make {msg: $"hyprctl rejected the scale: ($reply.stdout)($reply.stderr)"} }
    record $name scale $expr
}

def scale-set [name: string, scale: string]: nothing -> nothing {
    scale-apply $name $scale
    sleep $SCALE_SETTLE
    let applied = scale-get $name
    let scale = if (($applied | into float) - ($scale | into float) | math abs) < $SCALE_TOLERANCE {
        $scale
    } else {
        print -e $"hyprland adjusted the scale to ($applied) \(asked for ($scale)\); persisting the real value"
        $applied
    }
    persisted-scale-set $name $scale
    notify "Monitor scale" $"($name) at ($scale)x"
}

def layout-set [name: string, action: string, source: string]: nothing -> nothing {
    let all = monitors
    let monitor = $all | where name == $name | get 0?
    if $monitor == null { error make {msg: $"no such monitor: ($name)"} }
    let scale = if $monitor.scale > 0 { $monitor.scale | into string } else { "auto" }
    let active = $all | where (not $it.disabled) and $it.mirrorOf == "none"
    let fields = match $action {
        # hl.monitor merges, so disabled and mirror are cleared explicitly
        extend => {
            let position = persisted-get $name position auto
            {mode: (persisted-get $name mode highrr), position: $position, scale: $scale, disabled: false, mirror: ""}
        }
        off => {
            if ($active | where name != $name | is-empty) { error make {msg: "refusing to disable the last active monitor"} }
            {disabled: true}
        }
        mirror => {
            if $source in ["" $name] { error make {msg: $"mirror needs a source other than ($name)"} }
            if $source not-in $active.name {
                error make {msg: $"mirror source ($source) is not an active, unmirrored monitor"}
            }
            {mode: (persisted-get $name mode highrr), position: auto, scale: $scale, disabled: false, mirror: $source}
        }
        _ => { error make {msg: "layout action is one of extend, off, mirror"} }
    }
    let expr = lua-monitor ({output: $name} | merge $fields)
    ^hyprctl eval $expr
    record $name layout $expr
}

def scale-check [scale: string]: nothing -> nothing {
    if $scale !~ '^[0-9]+(\.[0-9]+)?$' { error make {msg: "scale must be a number"} }
}

def "main get" [monitor?: string] { scale-get ($monitor | default (monitor-default)) }

def "main label" [] { let monitor = monitor-default; $"󰍹 Scale: ($monitor) (scale-get $monitor)x" }

def "main list" [] {
    let rows = ^hyprctl -j monitors | from json | each {|m| $"($m.name)\t(mode-of $m)\t($m.scale)" }
    print ($rows | str join "\n")
}

def "main set" [scale: string, monitor?: string] { scale-check $scale; scale-set ($monitor | default (monitor-default)) $scale }
def "main live" [scale: string, monitor?: string] { scale-check $scale; scale-apply ($monitor | default (monitor-default)) $scale }
def "main layout" [monitor: string, action: string, source: string = ""] { layout-set $monitor $action $source }

def "main toggle" [] {
    let monitor = monitor-default
    let current = scale-get $monitor | into float
    scale-set $monitor ($SCALES | where ($it | into float) > $current + $SCALE_TOLERANCE | get 0? | default $SCALES.0)
}

def "main reapply" [] { reapply }
def main [] { main label }
