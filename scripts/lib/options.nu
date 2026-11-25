# Option resolution: default < detected < platform < profile; root never sees the profile.

use state.nu [xdg]

const SPEC_KEYS = [type default doc label group choices pattern min max step apply scope toggle]
const SPEC_REQUIRED = [type default doc]
export const OPTION_APPLY = [live relink relogin reboot]
export const OPTION_SCOPE = [machine user]
const OPTION_APPLY_DEFAULT = "relink"
const OPTION_SCOPE_DEFAULT = "machine"
export const OPTION_ENABLE = "enable"
const EVENTS_FILE = "dot/events.jsonl"
const EVENTS_MAX_BYTES = 1048576
const NUON_INDENT = 4
const NUON_QUOTES = ['"' "'"]
const NUON_OPEN = ["{" "["]
const NUON_CLOSE = ["}" "]"]

# Whether value fits a spec type; a trailing ? admits null, an int passes as float, a string as path.
export def option-type-ok [type: string, value: any]: nothing -> bool {
    let actual = $value | describe
    let wanted = $type | str trim --right --char "?"
    let base = $actual | split row "<" | first
    if $type == "any" or $actual == $wanted or $base == $wanted { return true }
    if ($type | str ends-with "?") and $actual == "nothing" { return true }
    match [$wanted $base] {
        ["float" "int"] | ["path" "string"] => true
        [$w "table"] if ($w == "list" or ($w | str starts-with "list<record") or ($w | str starts-with "table")) => true
        _ => (($wanted | str starts-with "list<") and $actual == "list<any>")
    }
}

def spec-errors [module: record, name: string, spec: record]: nothing -> list<string> {
    let file = $"configs/($module.id)/mod.nu"
    let where = $"($file): option ($name)"
    let cols = $spec | columns
    let unknown = $cols | where $it not-in $SPEC_KEYS | each { $"($where): unknown spec key ($in)" }
    let missing = $SPEC_REQUIRED | where $it not-in $cols | each { $"($where): no ($in)" }
    let enums = [
        (if $spec.apply not-in $OPTION_APPLY { $"($where): apply ($spec.apply) is not one of ($OPTION_APPLY | str join ', ')" })
        (if $spec.scope not-in $OPTION_SCOPE { $"($where): scope ($spec.scope) is not one of ($OPTION_SCOPE | str join ', ')" })
        # dot set applies a live option through the apply verb or the toggle; with neither it changes nothing
        (if $spec.apply == "live" and "apply" not-in $module.native and $spec.toggle? == null { $"($where): apply live needs an apply verb or a toggle" })
    ] | compact
    let default_bad = if ($missing | is-empty) { option-value-errors $module.id $name $spec $spec.default $file } else { [] }
    $unknown ++ $missing ++ $enums ++ $default_bad
}

# Why value is not valid for spec (type, choices, pattern, min, max), each line naming file and option; empty when fine.
export def option-value-errors [id: string, name: string, spec: record, value: any, file: string]: nothing -> list<string> {
    let where = $"($file): ($id).($name)"
    if not (option-type-ok $spec.type $value) {
        return [$"($where): ($value | to nuon) is ($value | describe), wants ($spec.type)"]
    }
    let choices = $spec.choices? | default []
    # a list option's choices are its entries' (the settings window's multi pick)
    let listed = ($spec.type | str starts-with "list<") and $value != null
    let outside = if $listed { $value } else { [$value] } | where $it != null and $it not-in $choices
    if ($choices | is-not-empty) and ($outside | is-not-empty) {
        return [$"($where): (if $listed { $outside } else { $value } | to nuon) is not one of ($choices | to nuon)"]
    }
    # a string value matches the pattern regex, so a verb parsing it never sees a malformed one
    if ($value | describe) == string and ($spec.pattern? != null) and $value !~ $spec.pattern {
        return [$"($where): ($value | to nuon) does not match ($spec.pattern)"]
    }
    let low = if $value != null and ($spec.min? != null) and $value < $spec.min { [$"($where): ($value) is below ($spec.min)"] } else { [] }
    let high = if $value != null and ($spec.max? != null) and $value > $spec.max { [$"($where): ($value) is above ($spec.max)"] } else { [] }
    $low ++ $high
}

# A module's augmented option specs (name -> spec), its built-in defaults/sources and every spec error, all from one
# pass over module.options: the enable option is never itself validated.
def module-options-built [module: record]: nothing -> record {
    let enable = {
        type: bool
        default: $module.selected
        doc: "Run this module on this machine; the profile can turn off its user layer"
        label: "Enabled"
        apply: relink
        scope: user
    }
    let built = $module.options | insert $OPTION_ENABLE $enable | items {|name, spec|
        let augmented = $spec | merge {
            label: ($spec.label? | default ($name | str replace --all "_" " " | str capitalize))
            group: ($spec.group? | default $module.id)
            apply: ($spec.apply? | default $OPTION_APPLY_DEFAULT)
            scope: ($spec.scope? | default $OPTION_SCOPE_DEFAULT)
        }
        {name: $name, spec: $augmented, errors: (if $name == $OPTION_ENABLE { [] } else { spec-errors $module $name $augmented })}
    }
    {
        schema: ($built | each {|o| [$o.name $o.spec] } | into record)
        values: ($built | each {|o| [$o.name $o.spec.default?] } | into record)
        sources: ($built | each {|o| [$o.name default] } | into record)
        errors: ($built | get errors | flatten)
    }
}

# A module's option specs with the implicit enable option and label, group, apply and scope filled in.
export def options-schema [module: record]: nothing -> record {
    (module-options-built $module).schema
}

# Lands value on option name with its source, or adds the errors that kept it out. upsert, never update: platform.nu
# reaches this file from every mod.nu, where a module's update verb shadows nushell's.
def option-land [acc: record, name: string, value: any, source: string, errors: list<string>]: nothing -> record {
    if ($errors | is-not-empty) { return ($acc | upsert errors { append $errors }) }
    $acc | upsert values { upsert $name $value } | upsert sources { upsert $name $source }
}

# Why a layer may not turn on a module the layer below leaves off: root installs and runs only what the platform's
# groups select and its options keep on, and never reads the profile.
export def enable-raised [id: string, layer: record]: nothing -> string {
    let fix = if $layer.name == "profile" { "the profile only turns a module off" } else { "add its group to the platform's groups" }
    $"($layer.file): ($id).($OPTION_ENABLE) is true where the machine leaves it off; ($fix)"
}

# Each module's option values and where each came from, plus every error across the layers.
export def options-resolve [modules: table, platform: record, profile: any, detected: record = {}]: nothing -> record {
    let ids = $modules.id
    let layers = [
        {name: platform, file: ($platform.options_file | default "platform options"), values: $platform.options}
    ] ++ (if $profile == null { [] } else {
        [{name: profile, file: $profile.options_file, values: $profile.options}]
    })
    let unknown_modules = $layers | each {|layer|
        $layer.values | columns | where $it not-in $ids | each {|id| $"($layer.file): ($id) is no module" }
    } | flatten
    let set_ids = $layers | each { $in.values | columns } | flatten | uniq
    let detected_ids = $detected | columns
    let rows = $modules | par-each --keep-order {|module|
        if ($module.options | is-empty) and $module.id not-in $set_ids and $module.id not-in $detected_ids {
            return {id: $module.id, values: {enable: $module.selected}, sources: {enable: default}, errors: []}
        }
        let built = module-options-built $module
        let schema = $built.schema
        let entries = $detected | get --optional $module.id | default {} | items {|name, value| {name: $name, value: $value} } | where value != null
        # a detected value lands only on an option defaulting to null; one with a default would drop it unseen
        let shadowed = $entries | where {|d| ($schema | get --optional $d.name).default? != null }
        let start = {
            values: $built.values, sources: $built.sources
            errors: ($shadowed | each { $"configs/($module.id)/mod.nu: detect returned ($in.name), whose non-null default always wins" })
        }
        let detected_in = $entries | where name not-in $shadowed.name | reduce --fold $start {|d, acc|
            let spec = $schema | get --optional $d.name
            let bad = if $spec == null { [$"configs/($module.id)/mod.nu: detect returned ($d.name), no option of it"] } else {
                option-value-errors $module.id $d.name $spec $d.value $"configs/($module.id)/mod.nu detect"
            }
            option-land $acc $d.name $d.value detected $bad
        }
        let set = $layers | each {|layer| $layer.values | get --optional $module.id | default {} | items {|name, value| {layer: $layer, name: $name, value: $value} } }
        let resolved = $set | flatten | reduce --fold $detected_in {|e, acc|
            let spec = $schema | get --optional $e.name
            let bad = if $spec == null { [$"($e.layer.file): ($module.id).($e.name) is no option of it"] } else if $e.layer.name == "profile" and $spec.scope == "machine" {
                [$"($e.layer.file): ($module.id).($e.name) is a machine option, set it with dot set --machine"]
            } else if $e.name == $OPTION_ENABLE and $e.value == true and not ($acc.values | get $OPTION_ENABLE) {
                [(enable-raised $module.id $e.layer)]
            } else { option-value-errors $module.id $e.name $spec $e.value $e.layer.file }
            option-land $acc $e.name $e.value $e.layer.name $bad
        }
        {id: $module.id, values: $resolved.values, sources: $resolved.sources, errors: ($built.errors ++ $resolved.errors)}
    }
    {rows: ($rows | reject errors), errors: ($unknown_modules ++ ($rows | get errors | flatten))}
}

export def options-events-file []: nothing -> path {
    xdg runtime $EVENTS_FILE
}

# Appends a changed option to the events file dot internal watch follows; --error: stored, but applying it failed.
export def options-notify [key: string, value: any, source: string, runtime?: any, --error: any]: nothing -> nothing {
    let file = options-events-file
    mkdir ($file | path dirname)
    if ($file | path exists) and (ls $file | get 0.size | into int) > $EVENTS_MAX_BYTES { "" | save --force $file }
    $"({key: $key, value: $value, source: $source, runtime: $runtime, error: $error} | to json --raw)\n" | save --append $file
}

# Nuon with records and lists spelled out one entry per line, never the table form, key order kept; --inline on one
# line.
export def options-to-nuon [--indent: int = 0, --inline]: any -> string {
    let value = $in
    let pad = "" | fill --width ($indent * 4)
    let inner = $"($pad)    "
    match ($value | describe | split row "<" | first) {
        "record" => {
            if ($value | is-empty) { return "{}" }
            if $inline { return $"{($value | items {|k, v| $'(nuon-word $k): ($v | options-to-nuon --inline)' } | str join ', ')}" }
            let lines = $value | items {|k, v| $"($inner)(nuon-word $k): ($v | options-to-nuon --indent ($indent + 1))" }
            $"{\n($lines | str join "\n")\n($pad)}"
        }
        "list" | "table" => {
            if ($value | is-empty) { return "[]" }
            let nested = $value | any {|v| ($v | describe) =~ '^(record|list|table)' }
            if $inline { return $"[($value | each { options-to-nuon --inline } | str join ' ')]" }
            if not $nested { return $"[($value | each { options-to-nuon } | str join ' ')]" }
            let lines = $value | each {|v| $"($inner)($v | options-to-nuon --indent ($indent + 1))" }
            $"[\n($lines | str join "\n")\n($pad)]"
        }
        "string" => (nuon-word $value)
        _ => ($value | to nuon)
    }
}

# A string bare where nuon reads it back as the same string, quoted otherwise.
def nuon-word [text: string]: nothing -> string {
    # true, null, inf and nan would come back as other types
    let bare = $text =~ '^[A-Za-z_][A-Za-z0-9_.-]*$' and (try {
        let back = $"{x: ($text)}" | from nuon | get x
        ($back | describe) == "string" and $back == $text
    } catch { false })
    if $bare { $text } else { $text | to nuon }
}

# text, a nuon record, with the value at cell set (null stored as null); --remove drops the entry instead, with any
# record it leaves empty. Only the entry's own lines change, the rest of the text (comments, layout, quoting) stays; a
# one-line record is written anew, and text no splice reads back as wanted is written whole by options-to-nuon.
export def options-nuon-set [cell: list<string>, value: any, --remove]: string -> string {
    let text = $in
    let wanted = $text | from nuon | default {} | nuon-record-set $cell $value $remove
    let chars = $text | split chars
    let spliced = try { nuon-splice $chars (nuon-skip $chars 0) $cell $value $remove | str join } catch { null }
    if $spliced != null and (try { ($spliced | from nuon) == $wanted } catch { false }) { return $spliced }
    $"($wanted | options-to-nuon)\n"
}

def nuon-record-set [cell: list<string>, value: any, remove: bool]: record -> record {
    let record = $in
    let key = $cell.0
    if ($cell | length) == 1 {
        return (if $remove { $record | reject --optional $key } else { $record | upsert $key $value })
    }
    let inner = $record | get --optional $key | default {} | nuon-record-set ($cell | skip 1) $value $remove
    if ($inner | is-empty) { $record | reject --optional $key } else { $record | upsert $key $inner }
}

def nuon-splice [chars: list<string>, open: int, cell: list<string>, value: any, remove: bool]: nothing -> list<string> {
    if ($chars | get $open) != "{" { error make {msg: "no record"} }
    let scan = nuon-entries $chars $open
    let entry = $scan.entries | where key == $cell.0 | get --optional 0
    if ($chars | skip $open | first ($scan.close - $open) | all { $in != "\n" }) {
        let record = $chars | skip $open | first ($scan.close - $open + 1) | str join | from nuon | nuon-record-set $cell $value $remove
        # the file's own record goes multi-line, a nested one stays on its line
        let root = $open == (nuon-skip $chars 0)
        let text = $record | options-to-nuon --inline=(not $root) --indent ((nuon-indent $chars $open) // $NUON_INDENT)
        return (nuon-replace $chars $open ($scan.close + 1) $text)
    }
    let nested = $cell | length | $in > 1
    if $nested and $entry != null {
        if ($chars | get $entry.value_start) != "{" { error make {msg: "no record"} }
        let inner = nuon-splice $chars $entry.value_start ($cell | skip 1) $value $remove
        let left = nuon-entries $inner $open | get entries | where key == $cell.0 | first
        let empty = $inner | skip $left.value_start | first ($left.value_end - $left.value_start) | str join | from nuon | is-empty
        return (if $empty { nuon-entry-remove $inner $left } else { $inner })
    }
    if $remove { return (if $entry == null { $chars } else { nuon-entry-remove $chars $entry }) }
    let landed = if $nested { {} | nuon-record-set ($cell | skip 1) $value false } else { $value }
    if $entry == null {
        let line = nuon-line-start $chars $scan.close
        let indent = nuon-indent $chars $scan.close
        if ($line + $indent) != $scan.close { error make {msg: "closing brace after an entry"} }
        let pad = "" | fill --width ($indent + $NUON_INDENT)
        let text = $"($pad)(nuon-word $cell.0): ($landed | options-to-nuon --indent ($indent // $NUON_INDENT + 1))\n"
        return (nuon-replace $chars $line $line $text)
    }
    let text = $landed | options-to-nuon --indent ((nuon-indent $chars $entry.key_start) // $NUON_INDENT)
    nuon-replace $chars $entry.value_start $entry.value_end $text
}

def nuon-replace [chars: list<string>, start: int, end: int, text: string]: nothing -> list<string> {
    ($chars | first $start) ++ ($text | split chars) ++ ($chars | skip $end)
}

# An entry alone on its lines, with its trailing comma or comment; any other is left to the whole rewrite.
def nuon-entry-remove [chars: list<string>, entry: record]: nothing -> list<string> {
    let start = nuon-line-start $chars $entry.key_start
    if ($start + (nuon-indent $chars $entry.key_start)) != $entry.key_start { error make {msg: "entry shares its line"} }
    let rest = $chars | skip $entry.value_end | take while { $in != "\n" } | str join
    if not ($rest =~ '^[ \t]*,?[ \t]*(#.*)?$') { error make {msg: "entry shares its line"} }
    nuon-replace $chars $start ($entry.value_end + ($rest | str length) + 1) ""
}

def nuon-line-start [chars: list<string>, at: int]: nothing -> int {
    $at - ($chars | first $at | reverse | take while { $in != "\n" } | length)
}

def nuon-indent [chars: list<string>, at: int]: nothing -> int {
    $chars | skip (nuon-line-start $chars $at) | take while { $in == " " } | length
}

# The index of the next char that is no blank, comma or comment.
def nuon-skip [chars: list<string>, from: int]: nothing -> int {
    let count = $chars | length
    mut at = $from
    while $at < $count {
        let c = $chars | get $at
        if $c == "#" {
            while $at < $count and ($chars | get $at) != "\n" { $at += 1 }
        } else if $c =~ '^[\s,]$' { $at += 1 } else { break }
    }
    $at
}

def nuon-string-end [chars: list<string>, open: int]: nothing -> int {
    let quote = $chars | get $open
    let count = $chars | length
    mut at = $open + 1
    mut end = -1
    while $end < 0 and $at < $count {
        let c = $chars | get $at
        if $quote == '"' and $c == "\\" { $at += 2 } else if $c == $quote { $end = $at + 1 } else { $at += 1 }
    }
    if $end < 0 { error make {msg: "unterminated string"} }
    $end
}

# The index after the value starting at from: a string, a record or list with its nested ones, or a bare word.
def nuon-value-end [chars: list<string>, from: int]: nothing -> int {
    let count = $chars | length
    let first = $chars | get $from
    if $first in $NUON_QUOTES { return (nuon-string-end $chars $from) }
    mut at = $from
    if $first not-in $NUON_OPEN {
        while $at < $count and not (($chars | get $at) =~ '^[\s,\]}]$') { $at += 1 }
        return $at
    }
    mut depth = 0
    mut end = -1
    while $end < 0 and $at < $count {
        let c = $chars | get $at
        if $c in $NUON_QUOTES {
            $at = nuon-string-end $chars $at
        } else if $c == "#" and ($chars | get ($at - 1)) =~ '^[\s,\[{]$' {
            while $at < $count and ($chars | get $at) != "\n" { $at += 1 }
        } else {
            if $c in $NUON_OPEN { $depth += 1 }
            if $c in $NUON_CLOSE { $depth -= 1 }
            $at += 1
            if $depth == 0 { $end = $at }
        }
    }
    if $end < 0 { error make {msg: "unclosed record or list"} }
    $end
}

# The record opening at open: each entry's key and where key and value start and end, and its closing brace.
def nuon-entries [chars: list<string>, open: int]: nothing -> record {
    mut at = $open + 1
    mut entries = []
    $at = nuon-skip $chars $at
    while ($chars | get $at) != "}" {
        let key_start = $at
        let key_end = if ($chars | get $at) in $NUON_QUOTES { nuon-string-end $chars $at } else {
            $at + ($chars | skip $at | take while { $in != ":" and not ($in =~ '^\s$') } | length)
        }
        let word = $chars | skip $key_start | first ($key_end - $key_start) | str join
        let key = if ($word | str substring 0..0) in $NUON_QUOTES { $word | from nuon } else { $word }
        $at = $key_end + ($chars | skip $key_end | take while { $in =~ '^[ \t]$' } | length)
        if ($chars | get $at) != ":" { error make {msg: $"no colon after ($word)"} }
        let value_start = nuon-skip $chars ($at + 1)
        let value_end = nuon-value-end $chars $value_start
        $entries = $entries | append {key: $key, key_start: $key_start, value_start: $value_start, value_end: $value_end}
        $at = nuon-skip $chars $value_end
    }
    {entries: $entries, close: $at}
}
