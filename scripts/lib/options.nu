# Option resolution: default < detected < platform < profile; root never sees the profile.

use state.nu [xdg]

const SPEC_KEYS = [type default doc label group choices min max step apply scope toggle]
const SPEC_REQUIRED = [type default doc]
export const OPTION_APPLY = [live relink relogin reboot]
export const OPTION_SCOPE = [machine user]
const OPTION_APPLY_DEFAULT = "relink"
const OPTION_SCOPE_DEFAULT = "machine"
export const OPTION_ENABLE = "enable"
const EVENTS_FILE = "dot/events.jsonl"
const EVENTS_MAX_BYTES = 1048576

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
    let id = $module.id
    let cols = $spec | columns
    let unknown = $cols | each {|k| if $k in $SPEC_KEYS { null } else { $"configs/($id)/mod.nu: option ($name): unknown spec key ($k)" } } | compact
    let missing = $SPEC_REQUIRED | each {|k| if $k in $cols { null } else { $"configs/($id)/mod.nu: option ($name): no ($k)" } } | compact
    let apply = $spec.apply? | default $OPTION_APPLY_DEFAULT
    let scope = $spec.scope? | default $OPTION_SCOPE_DEFAULT
    let enums = [
        (if $apply in $OPTION_APPLY { null } else { $"configs/($id)/mod.nu: option ($name): apply ($apply) is not one of ($OPTION_APPLY | str join ', ')" })
        (if $scope in $OPTION_SCOPE { null } else { $"configs/($id)/mod.nu: option ($name): scope ($scope) is not one of ($OPTION_SCOPE | str join ', ')" })
        # dot set applies a live option through the apply verb or the toggle; with neither it changes nothing
        (if $apply != "live" or "apply" in $module.native or $spec.toggle? != null { null } else { $"configs/($id)/mod.nu: option ($name): apply live needs an apply verb or a toggle" })
    ] | compact
    let default_bad = if ($missing | is-empty) { option-value-errors $id $name $spec $spec.default $"configs/($id)/mod.nu" } else { [] }
    $unknown ++ $missing ++ $enums ++ $default_bad
}

# Why value is not valid for spec (type, choices, min, max), each line naming file and option; empty when fine.
export def option-value-errors [id: string, name: string, spec: record, value: any, file: string]: nothing -> list<string> {
    let where = $"($file): ($id).($name)"
    if not (option-type-ok $spec.type $value) {
        return [$"($where): ($value | to nuon) is ($value | describe), wants ($spec.type)"]
    }
    let choices = $spec.choices? | default []
    if ($choices | is-not-empty) and $value != null and $value not-in $choices {
        return [$"($where): ($value | to nuon) is not one of ($choices | to nuon)"]
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
        values: ($built | each {|o| [$o.name $o.spec.default] } | into record)
        sources: ($built | each {|o| [$o.name default] } | into record)
        errors: ($built | get errors | flatten)
    }
}

# A module's option specs with the implicit enable option and label, group, apply and scope filled in.
export def options-schema [module: record]: nothing -> record {
    (module-options-built $module).schema
}

# Lands value on option name with its source, or adds the errors that kept it out.
def option-land [acc: record, name: string, value: any, source: string, errors: list<string>]: nothing -> record {
    if ($errors | is-not-empty) { return ($acc | update errors { append $errors }) }
    $acc | update values { upsert $name $value } | update sources { upsert $name $source }
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

# Nuon with records and lists spelled out one entry per line, never the table form, key order kept.
export def options-to-nuon [--indent: int = 0]: any -> string {
    let value = $in
    let pad = "" | fill --width ($indent * 4)
    let inner = $"($pad)    "
    match ($value | describe | split row "<" | first) {
        "record" => {
            if ($value | is-empty) { return "{}" }
            let lines = $value | items {|k, v| $"($inner)(nuon-word $k): ($v | options-to-nuon --indent ($indent + 1))" }
            $"{\n($lines | str join "\n")\n($pad)}"
        }
        "list" | "table" => {
            if ($value | is-empty) { return "[]" }
            let nested = $value | any {|v| ($v | describe) =~ '^(record|list|table)' }
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
