# dot set: read, store and apply module options; the option schema itself is options.nu.

const REPO = path self ../..
use log.nu *
use cli.nu [concat]
use state.nu [save-atomic]
use options.nu [OPTION_ENABLE options-schema option-value-errors options-notify options-to-nuon]
use pipeline.nu [pipeline-load pipeline-plan pipeline-apply]
use run.nu [link-run unlink-run admin system-part pending-exit]

def toggle-script [name: string]: nothing -> path {
    $REPO | path join scripts toggles $"toggle-($name).nu"
}

def option-runtime [spec: record]: nothing -> any {
    if ($spec.toggle? | default null) == null { return null }
    try { ^(toggle-script $spec.toggle) get | str trim } catch { null }
}

export def options-list [mod: any, json: bool]: nothing -> any {
    let ctx = pipeline-load $REPO user
    let mods = $ctx.modules | where {|m| $mod == null or $m.id == $mod }
    if $json {
        let modules = $mods | each {|m|
            let options = options-schema $m | items {|key, spec|
                $spec | reject --optional toggle | merge {
                    key: $key
                    value: ($m.cfg | get $key)
                    source: ($m.sources | get $key)
                    runtime: (if $spec.apply == "live" { option-runtime $spec } else { null })
                }
            }
            {name: $m.id, label: $m.id, doc: ($m.meta.doc? | default ""), options: $options}
        }
        return ({modules: $modules} | to json --raw)
    }
    $mods | each {|m| options-schema $m | items {|key, spec| {module: $m.id, option: $key, value: ($m.cfg | get $key), source: ($m.sources | get $key)} } }
    | concat | where {|r| $mod != null or $r.option != "enable" or not $r.value }
}

export def option-target [target: string]: nothing -> record {
    let parts = $target | parse --regex '^(?<mod>.+)\.(?<key>[a-z][a-z0-9_]*)$' | get --optional 0
    if $parts == null { error make {msg: $"($target): want <group/module>.<option>"} }
    $parts
}

export def option-write [mod: string, key: string, value: any, machine: bool]: nothing -> record {
    let ctx = pipeline-load $REPO user
    let m = $ctx.modules | where id == $mod | get --optional 0
    if $m == null { error make {msg: $"no module ($mod); dot plan --modules lists them"} }
    let spec = options-schema $m | get --optional $key
    if $spec == null { error make {msg: $"($mod) has no option ($key); dot set ($mod) lists them"} }
    let bad = if $value == null { [] } else { option-value-errors $mod $key $spec $value "dot set" }
    if ($bad | is-not-empty) { error make {msg: ($bad | str join "\n")} }
    if $spec.scope == "machine" and not $machine { error make {msg: $"($mod).($key) is a machine option: dot set --machine"} }
    let file = if $machine { $ctx.platform.options_file } else { $ctx.profile.options_file }
    if $file == null or ($file | str starts-with "/etc/") { error make {msg: $"this machine's options are root's ($file | default '/etc/dotfiles'), not settable from here"} }
    let current = if ($file | path exists) { open $file } else { {} }
    let cell = [$mod $key] | into cell-path
    let updated = if $value == null { $current | reject --optional $cell } else { $current | upsert $cell $value }
    $updated | items {|id, opts| {id: $id, opts: $opts} } | where ($it.opts | is-not-empty) | reduce --fold {} {|e, acc| $acc | insert $e.id $e.opts }
    | options-to-nuon | $"($in)\n" | save-atomic $file
    let resolved = pipeline-load $REPO user | get modules | where id == $mod | first
    {module: $m, spec: $spec, value: ($resolved.cfg | get $key), source: ($resolved.sources | get $key), machine: $machine}
}

export def option-apply [target: string, set: record]: nothing -> nothing {
    mut results = []
    mut toggle_error = ""
    mut runtime: any = null
    match $set.spec.apply {
        "live" => {
            if "apply" in $set.module.native {
                let ctx = pipeline-load $REPO user
                $results = pipeline-apply $ctx (pipeline-plan $ctx apply [$set.module.id] true) apply 1
            } else if ($set.spec.toggle? | default null) != null {
                let argv = match ($set.value | describe) { "bool" => [(if $set.value { "on" } else { "off" })], _ => [set ($set.value | into string)] }
                let toggled = ^(toggle-script $set.spec.toggle) ...$argv | complete
                if ($toggled.stdout | str trim | is-not-empty) { print ($toggled.stdout | str trim) }
                if $toggled.exit_code != 0 {
                    $toggle_error = $"toggle-($set.spec.toggle) exited ($toggled.exit_code): ($toggled.stderr | str trim | lines | last 1 | str join '')"
                }
                $runtime = option-runtime $set.spec
            }
        }
        $apply => {
            if ($target | str ends-with $".($OPTION_ENABLE)") and $set.value == false and ($set.module.native | is-not-empty) {
                $results = unlink-run $set.module.id
                print $"note: ($set.module.id) unlinked; dot module remove ($set.module.id) also drops its packages"
            } else {
                # modules listing this one in meta.deps read its options through cfg.deps: they re-link with it
                let readers = pipeline-load $REPO user | get modules
                    | where {|m| $set.module.id in $m.meta.deps and "link" in $m.verbs and $m.cfg.enable } | get id
                let ids = (if "link" in $set.module.verbs { [$set.module.id] } else { [] }) ++ $readers
                if ($ids | is-not-empty) { $results = link-run $ids false }
            }
            if ($set.spec.scope == "machine" or $set.machine) and "system" in $set.module.verbs and (admin) { system-part $target }
            if $apply != "relink" {
                log-note $"($target) takes effect after a ($apply)"
            }
        }
    }
    let failed = $results | where not ok | each {|r| $"($r.id): ($r.error | default 'failed')" }
    let error = if ($failed | is-not-empty) { $"stored, the apply failed: ($failed | str join '; ')" } else if $toggle_error != "" { $"stored, ($toggle_error)" } else { null }
    options-notify $target $set.value $set.source $runtime --error $error
    if $error != null { error make {msg: $"($target): ($error)"} }
    pending-exit
}
