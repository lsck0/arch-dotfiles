#!/usr/bin/env -S nu --no-config-file
use lib.nu [status-record status-print notify state-set state-file]

const DOT = path self ../dot.nu
const HYPRLAND = "desktop/hyprland"
const SCALES = ["1" "1.25" "1.5" "2"]
const SCALE_TOLERANCE = 0.01
const SCALE_SETTLE = 400ms
const REFRESH_DECIMALS = 5

def instance []: nothing -> string { $env.HYPRLAND_INSTANCE_SIGNATURE? | default "" }

def monitors []: nothing -> table { ^hyprctl -j monitors all | from json }

def monitor-find [name: string]: nothing -> any { monitors | where name == $name | get 0? }

def monitor-default []: nothing -> string {
    let active = ^hyprctl -j monitors | from json
    $active | where focused | get name.0? | default ($active | get name.0)
}

def eval-checked [expr: string, what: string]: nothing -> nothing {
    let reply = ^hyprctl eval $expr | complete
    if $reply.stdout !~ ok { error make {msg: $"hyprctl rejected the ($what): ($reply.stdout)($reply.stderr)"} }
}

def scale-get [name: string]: nothing -> string { monitor-find $name | get scale | into string }

def mode-of [monitor: record]: nothing -> string {
    $"($monitor.width)x($monitor.height)@($monitor.refreshRate | into string --decimals $REFRESH_DECIMALS)"
}

def monitors-persisted []: nothing -> list<record> {
    ^$DOT set $HYPRLAND --json | from json | get modules.0.options | where key == monitors | get 0.value | default []
}

def persisted-get [name: string, key: string, fallback: string]: nothing -> string {
    monitors-persisted | where output == $name | get --optional 0 | get --optional $key | default $fallback | into string
}

def persisted-scale-set [name: string, scale: string]: nothing -> nothing {
    let monitors = monitors-persisted
    let current = monitor-find $name
    let entry = $monitors | where output == $name | get --optional 0
        | default {output: $name, mode: (mode-of $current), position: $"($current.x)x($current.y)"}
    let updated = $monitors | where output != $name | append ($entry | upsert scale ($scale | into float)) | sort-by output
    ^$DOT set --machine $"($HYPRLAND).monitors" ($updated | to json --raw)
}

def record [name: string, kind: string, expr: string]: nothing -> nothing {
    state-set $"monitor-($name)-($kind)" $"(instance) ($expr)" --volatile
}

def reapply []: nothing -> nothing {
    let saved = [layout scale] | each {|kind|
        glob (state-file $"monitor-*-($kind)" --volatile) | each { open --raw $in | split row --number 2 " " }
    } | flatten | where { $in.0 == (instance) } | each { $in.1 }
    # a scale expression re-enables its output: a monitor turned off (lid closed) goes off again last
    for expr in ($saved ++ ($saved | where { $in =~ 'disabled = true' })) { ^hyprctl eval $expr o> /dev/null }
}

def lua-monitor [fields: record]: nothing -> string {
    let body = $fields | items {|key, value|
        $"($key) = (if ($value | describe) == string { $'"($value)"' } else { $value | into string })"
    }
    $"hl.monitor\({ ($body | str join ', ') }\)"
}

def scale-apply [name: string, scale: string]: nothing -> nothing {
    let monitor = monitor-find $name
    if $monitor == null { error make {msg: $"unknown monitor: ($name)"} }
    let position = $"($monitor.x)x($monitor.y)"
    let expr = lua-monitor {output: $name, mode: (mode-of $monitor), position: $position, scale: ($scale | into float)}
    eval-checked $expr scale
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
    eval-checked $expr layout
    record $name layout $expr
}

def scale-check [scale: string]: nothing -> nothing {
    if $scale !~ '^[0-9]+(\.[0-9]+)?$' { error make {msg: "scale must be a number"} }
}

def "main get" [monitor?: string, --json] {
    let monitor = $monitor | default (monitor-default)
    let scale = scale-get $monitor
    let shown = try { $scale | into float | math round --precision 2 } catch { $scale }
    status-print (status-record "Monitor scale" $scale --text $"($monitor) ($shown)x" --states $SCALES) $json
}

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
def main [] { main get }
