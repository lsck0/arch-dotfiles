# dot set: read, store and apply module options and the machine's platform keys; their schemas are options.nu and
# platform.nu.

const REPO = path self ../..
use log.nu *
use state.nu [save-atomic]
use options.nu [OPTION_ENABLE options-schema option-value-errors options-notify options-nuon-set]
use platform.nu [PLATFORM_TARGET platform-load platform-spec platform-rows platform-errors platform-value-errors]
use pipeline.nu [module-get pipeline-load pipeline-plan pipeline-apply]
use run.nu [link-run unlink-run admin system-part pending-exit pending-add]
use modules.nu [modules-discover]
use usage.nu [die]

const OPTION_TARGET = '^(?<mod>.+)\.(?<key>[a-z][a-z0-9_]*)$'

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
        let platform = if $mod == null { {platform: (platform-list true)} } else { {} }
        return ({modules: $modules} | merge $platform | to json --raw)
    }
    $mods | each {|m| options-schema $m | items {|key, spec| {module: $m.id, option: $key, value: ($m.cfg | get $key), source: ($m.sources | get $key)} } }
    | flatten | where {|r| $mod != null or $r.option != $OPTION_ENABLE or not $r.value }
}

# Exits 2 on a target that names no module, or no option of its module. Called before a run is opened, so a typo is
# misuse and never the last run.
export def option-target-check [target: string]: nothing -> nothing {
    if $target == $PLATFORM_TARGET { return }
    let cell = platform-target $target
    if $cell != null {
        if (platform-spec $cell) == null { die --misuse $"the platform has no key ($cell | str join '.'); dot set ($PLATFORM_TARGET) lists them" }
        return
    }
    let modules = modules-discover $REPO []
    if $target in $modules.id { return }
    let parts = $target | parse --regex $OPTION_TARGET | get --optional 0
    let id = $parts.mod? | default $target
    let m = $modules | where id == $id | get --optional 0
    if $m == null { die --misuse $"no module ($id); dot plan --modules lists them" }
    if $parts.key not-in (options-schema $m | columns) {
        die --misuse $"($id) has no option ($parts.key); dot set ($id) lists them"
    }
}

# A checked target that is no module id, as its module and option.
export def option-target [target: string]: nothing -> record {
    $target | parse --regex $OPTION_TARGET | first
}

export def option-write [mod: string, key: string, value: any, machine: bool]: nothing -> record {
    let ctx = pipeline-load $REPO user
    let m = module-get $ctx $mod
    let spec = options-schema $m | get --optional $key
    if $spec == null { error make {msg: $"($mod) has no option ($key); dot set ($mod) lists them"} }
    let bad = if $value == null { [] } else { option-value-errors $mod $key $spec $value "dot set" }
    if ($bad | is-not-empty) { error make {msg: ($bad | str join "\n")} }
    if $spec.scope == "machine" and not $machine { error make {msg: $"($mod).($key) is a machine option, set it with dot set --machine ($mod).($key) <value>"} }
    let file = if $machine { $ctx.platform.options_file } else { $ctx.profile.options_file }
    if not (file-writable $file) { error make {msg: $"this machine's options are root's ($file | default '/etc/dotfiles'), not settable from here"} }
    let text = if ($file | path exists) { open --raw $file } else { "{}\n" }
    let updated = $text | options-nuon-set [$mod $key] $value
    if $updated != $text { $updated | save-atomic $file }
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
                # modules listing this one in meta.deps or meta.reads read its options through cfg.deps: they re-link with it
                let readers = pipeline-load $REPO user | get modules
                    | where {|m| $set.module.id in ($m.meta.deps ++ ($m.meta.reads? | default [])) and "link" in $m.verbs and $m.cfg.enable }
                    | get id
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

# What dot set writes itself: a file in the checkout or the profile, never root's under /etc.
def file-writable [file: any]: nothing -> bool {
    $file != null and not ($file | str starts-with "/etc/")
}

# The cell path below the platform file a target names, null for a target that is no platform key.
export def platform-target [target: string]: nothing -> any {
    let prefix = $"($PLATFORM_TARGET)."
    if not ($target | str starts-with $prefix) { return null }
    $target | str substring ($prefix | str length).. | split row "."
}

# The platform keys: key, value and source; --json adds each one's spec and the file, for the settings window. Every
# key is fixed (read only) where the file is root's.
export def platform-list [json: bool]: nothing -> any {
    let platform = platform-load $REPO
    let writable = file-writable $platform.file
    let rows = platform-rows $REPO $platform | each {|r| $r | merge {fixed: ($r.fixed or not $writable), scope: machine} }
    if not $json { return ($rows | select key value source) }
    let label = if $platform.file == null { $PLATFORM_TARGET } else { $platform.file | path parse | get stem }
    {name: $PLATFORM_TARGET, label: $label, file: $platform.file, writable: $writable, options: $rows}
}

# Stores value (null: unset) at the platform key cell in the machine's platform file: validated like the whole file,
# only the key's own lines rewritten.
export def platform-write [cell: list<string>, value: any]: nothing -> record {
    let target = $cell | prepend $PLATFORM_TARGET | str join "."
    let spec = platform-spec $cell
    if $spec.fixed { error make {msg: $"($target) names the platform, it is set at install"} }
    let file = (platform-load $REPO).file
    if not (file-writable $file) { error make {msg: $"this machine's platform is root's ($file | default '/etc/dotfiles/platform.nuon'), not settable from here"} }
    let bad = if $value == null { [] } else { platform-value-errors $REPO $cell $value "dot set" }
    if ($bad | is-not-empty) { error make {msg: ($bad | str join "\n")} }
    let text = open --raw $file
    let updated = $text | options-nuon-set $cell $value
    let errors = platform-errors $REPO ($updated | from nuon) $file
    if ($errors | is-not-empty) { error make {msg: ($errors | str join "\n")} }
    if $updated != $text { $updated | save-atomic $file }
    let row = platform-rows $REPO (platform-load $REPO) | where key == ($cell | str join ".") | first
    {spec: $spec, value: $row.value, source: $row.source, changed: ($updated != $text)}
}

# A stored platform key's apply: a changed apply key waits for the next dot apply (pending, exit 3), a packages key for
# the next dot apply --packages; a live one is read where it is used.
export def --env platform-apply [target: string, set: record]: nothing -> nothing {
    if $set.changed {
        match $set.spec.apply {
            "apply" => {
                pending-add $target
                log-note $"($target): takes effect on the next dot apply"
            }
            "packages" => (log-note $"($target): takes effect on the next dot apply --packages")
            _ => {}
        }
    }
    options-notify $target $set.value $set.source
    pending-exit
}
