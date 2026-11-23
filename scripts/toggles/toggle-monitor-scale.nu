#!/usr/bin/env -S nu --no-config-file
use lib.nu [DOT status-record status-print notify state-set state-file hyprland-instance option-value]

const HYPRLAND = "desktop/hyprland"
# 1.67 is the 4K monitors' own setting (3840 / 1.67 = 2304 logical px wide)
const SCALES = ["1" "1.25" "1.5" "1.67" "2"]
const SCALE_TOLERANCE = 0.01
const SCALE_SETTLE = 400ms
const REFRESH_DECIMALS = 5
const RELATIONS = [left-of right-of above below]

def monitors []: nothing -> table { ^hyprctl -j monitors all | from json }

def monitor-get [name: string]: nothing -> record {
    let monitor = monitors | where name == $name | get 0?
    if $monitor == null { error make {msg: $"no monitor ($name); toggle-monitor-scale.nu list lists them"} }
    $monitor
}

def monitor-is-active [monitor: record]: nothing -> bool { not $monitor.disabled and $monitor.mirrorOf == "none" }

def monitor-default []: nothing -> string {
    let active = ^hyprctl -j monitors | from json
    $active | where focused | get name.0? | default ($active | get name.0)
}

def scale-get [name: string]: nothing -> string { monitor-get $name | get scale | into string }

def mode-of [monitor: record]: nothing -> string {
    $"($monitor.width)x($monitor.height)@($monitor.refreshRate | into string --decimals $REFRESH_DECIMALS)"
}

# A mode as hl.monitor takes it, `<w>x<h>@<hz>` with the refresh rate's trailing zeros dropped, from either an
# availableModes entry (`3840x2160@144.00Hz`) or a saved mode.
export def mode-normalize [mode: string]: nothing -> string {
    let parsed = $mode | parse --regex '^(?<w>\d+)x(?<h>\d+)@(?<hz>\d+(\.\d+)?)(Hz)?$' | get --optional 0
    if $parsed == null { error make {msg: $"mode ($mode) is not <width>x<height>@<hz>"} }
    let hz = $parsed.hz | str replace --regex '(\.\d*?)0+$' '$1' | str replace --regex '\.$' ''
    $"($parsed.w)x($parsed.h)@($hz)"
}

def transform-swaps-axes [transform: int]: nothing -> bool { $transform mod 2 == 1 }

# The monitor's size in the layout's logical pixels: its mode over its scale, turned with its transform.
export def monitor-logical-size [monitor: record]: nothing -> record {
    let width = $monitor.width / $monitor.scale | math round | into int
    let height = $monitor.height / $monitor.scale | math round | into int
    if (transform-swaps-axes ($monitor.transform? | default 0)) { {width: $height, height: $width} } else { {width: $width, height: $height} }
}

# Where a monitor goes to sit beside another, edges touching, top or left edges aligned.
export def position-relative [monitor: record, other: record, relation: string]: nothing -> record {
    let size = monitor-logical-size $monitor
    let beside = monitor-logical-size $other
    match $relation {
        left-of => {x: ($other.x - $size.width), y: $other.y}
        right-of => {x: ($other.x + $beside.width), y: $other.y}
        above => {x: $other.x, y: ($other.y - $size.height)}
        below => {x: $other.x, y: ($other.y + $beside.height)}
        _ => { error make {msg: $"relation is one of ($RELATIONS | str join ', ')"} }
    }
}

# Shifts the whole layout so its top left corner is 0x0: a monitor placed left of or above the origin moves the rest.
export def positions-normalize [placed: list<record>]: nothing -> list<record> {
    if ($placed | is-empty) { return [] }
    let dx = $placed.x | math min
    let dy = $placed.y | math min
    $placed | each {|p| $p | merge {x: ($p.x - $dx), y: ($p.y - $dy)} }
}

def monitors-persisted []: nothing -> list<record> { option-value $HYPRLAND monitors | default [] }

# The saved mode and position of a monitor, highrr and auto where none is saved.
def persisted-of [name: string]: nothing -> record {
    let saved = monitors-persisted | where output == $name | get --optional 0
    {mode: ($saved.mode? | default highrr), position: ($saved.position? | default auto)}
}

def monitor-entry [monitor: record]: nothing -> record {
    {output: $monitor.name, mode: (mode-of $monitor), position: $"($monitor.x)x($monitor.y)", scale: $monitor.scale}
}

# Merges each change ({output, ...fields}) into that output's saved hl.monitor; an unsaved output starts from its
# live mode, position and scale.
export def monitors-merge [saved: list<record>, live: list<record>, changes: list<record>]: nothing -> list<record> {
    $changes | reduce --fold $saved {|change, acc|
        let entry = $acc | where output == $change.output | get --optional 0
            | default (monitor-entry ($live | where name == $change.output | first))
        $acc | where output != $change.output | append ($entry | merge $change)
    } | sort-by output
}

def persisted-update [changes: list<record>]: nothing -> nothing {
    let updated = monitors-merge (monitors-persisted) (monitors) $changes
    ^nu --no-config-file $DOT set --machine $"($HYPRLAND).monitors" ($updated | to json --raw)
}

# In the order they were saved, as they ran live: a later expression for an output replaces the fields of an earlier
# one, so a scale saved before a mirror would otherwise undo it.
def reapply []: nothing -> nothing {
    let saved = [layout scale] | each {|kind| glob (state-file $"monitor-*-($kind)" --volatile) } | flatten
        | sort-by {|file| ls --directory $file | get 0.modified }
        | each { open --raw $in | split row --number 2 " " } | where { $in.0 == (hyprland-instance) } | each { $in.1 }
    # a scale expression re-enables its output: a monitor turned off (lid closed) goes off again last
    for expr in ($saved ++ ($saved | where { $in =~ 'disabled = true' })) { ^hyprctl eval $expr o> /dev/null }
}

def lua-monitor [fields: record]: nothing -> string {
    let body = $fields | items {|key, value|
        $"($key) = (if ($value | describe) == string { $'"($value)"' } else { $value | into string })"
    }
    $"hl.monitor\({ ($body | str join ', ') }\)"
}

# Runs one hl.monitor and keeps it, per output and kind, for reapply.
def monitor-eval [kind: string, fields: record]: nothing -> nothing {
    let expr = lua-monitor $fields
    let reply = ^hyprctl eval $expr | complete
    if $reply.stdout !~ ok { error make {msg: $"hyprctl rejected ($expr): ($reply.stdout)($reply.stderr)"} }
    state-set $"monitor-($fields.output)-($kind)" $"(hyprland-instance) ($expr)" --volatile
}

# The monitor as it runs with some fields changed, saved as a scale: a later one replaces it.
def geometry-apply [monitor: record, fields: record]: nothing -> nothing {
    monitor-eval scale (monitor-entry $monitor | merge $fields)
}

def scale-apply [name: string, scale: string]: nothing -> nothing {
    geometry-apply (monitor-get $name) {scale: ($scale | into float)}
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
    persisted-update [{output: $name, scale: ($scale | into float)}]
    notify "Monitor scale" $"($name) at ($scale)x"
}

def layout-set [name: string, action: string, source: string]: nothing -> nothing {
    let monitor = monitor-get $name
    let scale = if $monitor.scale > 0 { $monitor.scale | into string } else { "auto" }
    let active = monitors | where { monitor-is-active $in }
    let fields = match $action {
        extend => (persisted-of $name | merge {scale: $scale, disabled: false, mirror: ""})
        off => {
            if ($active | where name != $name | is-empty) { error make {msg: "refusing to disable the last active monitor"} }
            {disabled: true}
        }
        mirror => {
            if $source in ["" $name] { error make {msg: $"mirror needs a source other than ($name)"} }
            if $source not-in $active.name {
                error make {msg: $"mirror source ($source) is not an active, unmirrored monitor"}
            }
            {mode: (persisted-of $name).mode, position: auto, scale: $scale, disabled: false, mirror: $source}
        }
        _ => { error make {msg: "layout action is one of extend, off, mirror"} }
    }
    monitor-eval layout ({output: $name} | merge $fields)
}

def monitor-active [name: string]: nothing -> record {
    let monitor = monitor-get $name
    if not (monitor-is-active $monitor) { error make {msg: $"($name) is off or mirrored: extend it first"} }
    $monitor
}

# A new mode can leave the scale not dividing it: hyprland then picks a near one, which is what gets saved.
def mode-set [name: string, mode: string]: nothing -> nothing {
    let monitor = monitor-active $name
    let mode = mode-normalize $mode
    if $mode not-in ($monitor.availableModes | each { mode-normalize $in }) {
        error make {msg: $"($name) has no mode ($mode)"}
    }
    geometry-apply $monitor {mode: $mode}
    sleep $SCALE_SETTLE
    persisted-update [{output: $name, mode: $mode, scale: (monitor-get $name).scale}]
    notify "Monitor mode" $"($name) at ($mode) Hz"
}

def position-set [name: string, relation: string, other: string]: nothing -> nothing {
    if $name == $other { error make {msg: "a monitor is placed beside another one"} }
    let monitor = monitor-active $name
    let target = monitor-active $other
    let moved = position-relative $monitor $target $relation
    let active = monitors | where { monitor-is-active $in }
    let placed = $active | each {|m| if $m.name == $name { {name: $name} | merge $moved } else { $m | select name x y } }
        | positions-normalize $in
    let changed = $placed | where {|p| $active | where name == $p.name and x == $p.x and y == $p.y | is-empty }
    for p in $changed { geometry-apply ($active | where name == $p.name | first) {position: $"($p.x)x($p.y)"} }
    persisted-update ($changed | each {|p| {output: $p.name, position: $"($p.x)x($p.y)"} })
    notify "Monitor layout" $"($name) ($relation | str replace '-' ' ') ($other)"
}

def scale-check [scale: string]: nothing -> nothing {
    if $scale !~ '^[0-9]+(\.[0-9]+)?$' { error make {msg: "scale must be a number"} }
}

def "main get" [monitor?: string, --json] {
    let monitor = $monitor | default (monitor-default)
    let scale = scale-get $monitor
    let shown = $scale | into float | math round --precision 2
    status-print (status-record "Monitor scale" $scale --text $"($monitor) ($shown)x" --states $SCALES) $json
}

def "main list" [] {
    let rows = ^hyprctl -j monitors | from json | each {|m| $"($m.name)\t(mode-of $m)\t($m.scale)" }
    print ($rows | str join "\n")
}

def "main set" [scale: string, monitor?: string] { scale-check $scale; scale-set ($monitor | default (monitor-default)) $scale }
def "main live" [scale: string, monitor?: string] { scale-check $scale; scale-apply ($monitor | default (monitor-default)) $scale }
def "main layout" [monitor: string, action: string, source: string = ""] { layout-set $monitor $action $source }
def "main mode" [monitor: string, mode: string] { mode-set $monitor $mode }
def "main position" [monitor: string, relation: string, other: string] { position-set $monitor $relation $other }

def "main toggle" [] {
    let monitor = monitor-default
    let current = scale-get $monitor | into float
    scale-set $monitor ($SCALES | where ($it | into float) > $current + $SCALE_TOLERANCE | get 0? | default $SCALES.0)
}

def "main reapply" [] { reapply }
# Monitor scale: get [monitor] [--json] prints the scale, list the monitors, set <scale> [monitor] saves and applies
# one, live <scale> [monitor] applies it unsaved, toggle takes the next scale, a bare call prints the scale.
# mode <monitor> <w>x<h>@<hz> and position <monitor> left-of|right-of|above|below <other> save and apply too;
# layout <monitor> extend|off|mirror [source] lasts until the session ends.
def main [] { main get }
