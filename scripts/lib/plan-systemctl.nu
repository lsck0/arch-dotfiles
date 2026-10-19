#!/usr/bin/env -S nu --no-config-file

const ENABLED_STATES = [enabled enabled-runtime static alias indirect generated transient]
const CHANGE_VERBS = [
    enable disable reenable mask unmask start stop restart try-restart reload reload-or-restart try-reload-or-restart
    reset-failed kill preset link revert set-property isolate set-environment unset-environment import-environment
    daemon-reexec edit add-wants add-requires
]
const VALUE_FLAGS = [-M --machine -p --property -t --type -n --lines -o --output -s --signal]
const EXIT_INACTIVE = 3

def snapshot-read [file: path]: nothing -> table<unit: string, state: string> {
    if not ($file | path exists) {
        return []
    }
    open --raw $file | lines | where $it != "" | parse "{unit} {state}"
}

def glob-regex [pattern: string]: nothing -> string {
    $"^($pattern | str replace --all '.' '\.' | str replace --all '*' '.*' | str replace --all '?' '.')$"
}

def note [scope: string, verb: string, now: string, units: list<string>]: nothing -> nothing {
    let module = $env.DOTFILES_PLAN_MODULE? | default driver
    $"($module)\tsystemctl\t($units | str join ' ')\t--($scope) ($verb)($now)\n"
    | save --append ($env.DOTFILES_PLAN_DIR | path join notes)
}

def --wrapped main [...args: string]: nothing -> nothing {
    mut scope = "system"
    mut quiet = false
    mut now = ""
    mut state = ""
    mut skip = false
    mut words = []
    for arg in $args {
        if $skip {
            $skip = false
            continue
        }
        if $arg == "--user" { $scope = "user" } else if $arg == "--system" { $scope = "system"
        } else if $arg in [-q --quiet] { $quiet = true } else if $arg == "--now" { $now = " --now"
        } else if ($arg | str starts-with "--state=") { $state = $arg | str replace "--state=" ""
        } else if $arg in $VALUE_FLAGS { $skip = true
        } else if not ($arg | str starts-with "-") { $words = $words | append $arg }
    }
    let verb = $words | first | default ""
    let units = $words | skip 1
    let dir = $env.DOTFILES_PLAN_DIR
    let unit_files = $dir | path join $"unit-files.($scope)"
    let snapshot = snapshot-read $unit_files
    let active = if ($dir | path join $"active.($scope)" | path exists) {
        open --raw ($dir | path join $"active.($scope)") | lines
    } else { [] }
    match $verb {
        "is-enabled" => {
            let states = $units | each {|u| $snapshot | where unit == $u | get --optional state | last | default not-found }
            if not $quiet { $states | each { print $in } | ignore }
            if ($states | any {|s| $s not-in $ENABLED_STATES }) { exit 1 }
        }
        "is-active" => {
            let states = $units | each {|u| if $u in $active { "active" } else { "inactive" } }
            if not $quiet { $states | each { print $in } | ignore }
            if ("inactive" in $states) { exit $EXIT_INACTIVE }
        }
        "list-unit-files" => {
            let patterns = if ($units | is-empty) { ["*"] } else { $units }
            let states = $state | split row "," | where $it != ""
            $snapshot
            | where {|row| ($states | is-empty) or $row.state in $states }
            | where {|row| $patterns | any {|p| $row.unit =~ (glob-regex $p) } }
            | each {|row| print $"($row.unit) ($row.state)" } | ignore
        }
        "daemon-reload" => {}
        "cat" => { if ($units | any {|u| $snapshot | where unit == $u | is-empty }) { exit 1 } }
        $v if $v in $CHANGE_VERBS => {
            let changed = $units | where {|u|
                let current = $snapshot | where unit == $u | get --optional state | last | default ""
                let running = $u in $active
                match $v {
                    "enable" => (not ($current == "enabled" and ($now == "" or $running)))
                    "disable" => (not ($current != "enabled" and ($now == "" or not $running)))
                    "mask" => ($current != "masked")
                    _ => true
                }
            }
            if ($changed | is-not-empty) {
                note $scope $v $now $changed
            }
            let new_state = match $v {
                "enable" | "reenable" => "enabled"
                "disable" | "unmask" => "disabled"
                "mask" => "masked"
                _ => ""
            }
            if ($new_state | is-not-empty) {
                # bound into the sandbox alone, so the library comes from the checkout
                let lib = $env.DOTFILES | path join scripts lib
                {file: $unit_files, units: $units, state: $new_state} | to json --raw
                | ^flock $"($unit_files).lock" nu --no-config-file --stdin -I $lib ($lib | path join locked.nu) units-set
            }
        }
        _ => { exit 1 }
    }
}
