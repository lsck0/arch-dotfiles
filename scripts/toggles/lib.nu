
use ../lib/log.nu [log-err]

export const TOGGLES_DIR = path self .
const ROOT_HELPER = "/usr/local/bin/toggle-root"
const ADMIN_GROUP = "wheel"
const IPC_TIMEOUT_S = 3

# The state file of a toggle; --volatile puts it on tmpfs, for state whose tool resets on boot (tlp, rfkill ids).
export def state-file [name: string, --volatile]: nothing -> path {
    let dir = if $volatile {
        $env.XDG_RUNTIME_DIR | path join toggles
    } else {
        $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state) | path join toggles
    }
    mkdir $dir
    $dir | path join $name
}

# The stored state, "off" when none.
export def state-get [name: string, --volatile]: nothing -> string {
    let file = state-file $name --volatile=$volatile
    if ($file | path exists) { open --raw $file | str trim --right } else { "off" }
}

export def state-set [name: string, value: string, --volatile]: nothing -> nothing {
    $value | save --force (state-file $name --volatile=$volatile)
}

export def state-clear [name: string, --volatile]: nothing -> nothing {
    rm --force (state-file $name --volatile=$volatile)
}

def user-is-admin []: nothing -> bool {
    $ADMIN_GROUP in (^id -nG | str trim | split row " ")
}

# One unit per call: EnqueueUnitJobMany is refused before polkit can ask.
export def systemctl-guarded [verb: string, ...units: string]: nothing -> nothing {
    let ask = if (user-is-admin) { [] } else { [--no-ask-password] }
    for unit in $units { ^systemctl ...$ask $verb $unit }
}

# Runs the root helper through pkexec; a non-admin is turned away before its password dialog.
export def root-run [...args: string]: nothing -> nothing {
    if not (user-is-admin) {
        error make {msg: $"($args.0) needs an admin"}
    }
    ^pkexec $ROOT_HELPER ...$args
}

export def toggle-run [name: string, ...args: string]: nothing -> any {
    ^($TOGGLES_DIR | path join $"toggle-($name).nu") ...$args
}

# A machine without the module has no unit: the toggle is hidden there, not offered and failing.
export def unit-exists [unit: string]: nothing -> bool {
    (^systemctl cat $unit | complete).exit_code == 0
}

export def unit-active [unit: string]: nothing -> bool {
    (^systemctl is-active --quiet $unit | complete).exit_code == 0
}

# Bounded by a timeout, so a shell that is down or hung never blocks a toggle.
export def quickshell-call [target: string, ...args: string]: nothing -> string {
    ^timeout $IPC_TIMEOUT_S quickshell ipc -p ($nu.home-dir | path join .config quickshell) call $target ...$args
}

# Also pings the bar, which refreshes every reader of toggle state, so nothing polls.
export def notify [summary: string, body: string, --critical]: nothing -> nothing {
    quickshell-call toggles changed ($env.PROCESS_PATH | path basename) | complete | ignore
    let urgency = if $critical { [-u critical] } else { [] }
    ^timeout $IPC_TIMEOUT_S notify-send -a Toggles ...$urgency $summary $body | complete | ignore
}

# The element after `current` in the input list, wrapping; the first when `current` is not in it.
export def cycle-next [current: any]: list -> any {
    let list = $in
    let index = $list | enumerate | where item == $current | get index.0? | default (-1)
    $list | get (($index + 1) mod ($list | length))
}

# The record status.nu, the menu, the bar and settings read; `states` lists the resting value first.
export def status-record [
    label: string, state: string, --text: string, --states: list<string> = [], --available = true
]: nothing -> record {
    {
        name: ($env.PROCESS_PATH | path basename | str replace --regex '^toggle-(.*)\.nu$' '$1')
        label: $label
        state: $state
        text: ($text | default $state)
        states: $states
        on: (($states | is-not-empty) and $state != $states.0)
        available: $available
    }
}

# `get` prints the state alone, `get --json` the whole record.
export def status-print [status: record, json: bool]: nothing -> any {
    if $json { $status | to json --raw } else { $status.state }
}

# get/on/off/toggle for a switch; a failure exits 1.
export def switch-run [switch: record, action: string, --json]: nothing -> any {
    let available = if "available" in $switch { do $switch.available } else { true }
    let state = if $available and (do $switch.is-on) { "on" } else { "off" }
    let action = if $action == toggle { if $state == on { "off" } else { "on" } } else { $action }
    match $action {
        get => {
            status-print (status-record $switch.label $state --states [off on] --available=$available) $json
        }
        on | off => {
            try { do ($switch | get $action) } catch {|err|
                notify $switch.label $"Failed to turn ($action)" --critical
                with-env {LOG_TAG: ($env.PROCESS_PATH | path basename)} { log-err $err.msg }
                exit 1
            }
            notify $switch.label $"Turned ($action)"
        }
        _ => {
            print -e $"usage: ($env.PROCESS_PATH | path basename) {get [--json]|on|off|toggle}"
            exit 1
        }
    }
}

export def service-switch [label: string, unit: string]: nothing -> record {
    {
        label: $label
        available: {|| unit-exists $unit }
        is-on: {|| unit-active $unit }
        on: {|| ^systemctl --no-ask-password start $unit }
        off: {|| systemctl-guarded stop $unit }
    }
}

# A switch for an nmcli radio; on fails without the hardware, which the soft switch alone would report enabled.
export def radio-switch [label: string, radio: string]: nothing -> record {
    let hardware = $"($radio | str uppercase)-HW"
    let types = if $radio == wwan { [gsm wwan] } else { [$radio] }
    {
        label: $label
        available: {|| ^nmcli -t -f TYPE device | lines | any {|type| $type in $types } }
        is-on: {|| (^nmcli -t -f $"($hardware),($radio | str uppercase)" radio | complete).stdout == "enabled:enabled\n" }
        on: {||
            if (^nmcli -t -f $hardware radio | str trim) != enabled {
                error make {msg: $"no ($radio) hardware"}
            }
            ^nmcli radio $radio on
        }
        off: {|| ^nmcli radio $radio off }
    }
}
