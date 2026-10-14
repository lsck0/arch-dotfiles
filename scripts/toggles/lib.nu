use ../lib/log.nu [log-err]

export const TOGGLES_DIR = path self .
const ROOT_HELPER = "/usr/local/bin/toggle-root"
const ADMIN_GROUP = "wheel"
const IPC_TIMEOUT_S = 3

# volatile is tmpfs, for state whose tool resets on boot (tlp, rfkill ids): wiped with it, so it never goes stale
export def state-file [name: string, --volatile]: nothing -> path {
    let dir = if $volatile {
        $env.XDG_RUNTIME_DIR | path join toggles
    } else {
        $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state) | path join toggles
    }
    mkdir $dir
    $dir | path join $name
}

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

# polkit passes an admin unprompted except to lower a guard (configs/core/toggles); others are refused, never asked
def user-is-admin []: nothing -> bool {
    $ADMIN_GROUP in (^id -nG | str trim | split row " ")
}

export def systemctl-guarded [...args: string]: nothing -> nothing {
    if (user-is-admin) { ^systemctl ...$args } else { ^systemctl --no-ask-password ...$args }
}

# pkexec has no switch to skip the session's polkit agent, so a non-admin is turned away before its password dialog
export def root-run [...args: string]: nothing -> nothing {
    if not (user-is-admin) {
        error make {msg: $"($args.0) needs an admin"}
    }
    ^pkexec $ROOT_HELPER ...$args
}

export def toggle-run [name: string, ...args: string]: nothing -> any {
    ^($TOGGLES_DIR | path join $"toggle-($name).nu") ...$args
}

export def unit-active [unit: string]: nothing -> bool {
    (^systemctl is-active --quiet $unit | complete).exit_code == 0
}

# a shell that is down or hung never blocks a toggle
export def quickshell-call [target: string, ...args: string]: nothing -> string {
    ^timeout $IPC_TIMEOUT_S quickshell ipc -p ($nu.home-dir | path join .config quickshell) call $target ...$args
}

# the ping refreshes every reader of toggle state, so nothing polls
export def notify [summary: string, body: string, --critical]: nothing -> nothing {
    quickshell-call toggles changed ($env.PROCESS_PATH | path basename) | complete | ignore
    let urgency = if $critical { [-u critical] } else { [] }
    ^timeout $IPC_TIMEOUT_S notify-send -a Toggles ...$urgency $summary $body | complete | ignore
}

# the element after current, wrapping around; the first when current is absent
export def cycle-next [current: any]: list -> any {
    let list = $in
    let index = $list | enumerate | where item == $current | get index.0? | default (-1)
    $list | get (($index + 1) mod ($list | length))
}

# switch-run <switch> <action>: get, label, on, off or toggle for an on/off switch {label, is-on, on, off}
export def switch-run [switch: record, action: string]: nothing -> any {
    let state = if (do $switch.is-on) { "on" } else { "off" }
    let action = if $action == toggle { if $state == on { "off" } else { "on" } } else { $action }
    match $action {
        get => $state
        label => $"(if $state == on { '●' } else { '○' }) ($switch.label) \(($state)\)"
        on | off => {
            try { do ($switch | get $action) } catch {|err|
                notify $switch.label $"Failed to turn ($action)" --critical
                with-env {LOG_TAG: ($env.PROCESS_PATH | path basename)} { log-err $err.msg }
                exit 1
            }
            notify $switch.label $"Turned ($action)"
        }
        _ => {
            print -e $"usage: ($env.PROCESS_PATH | path basename) {get|label|on|off|toggle}"
            exit 1
        }
    }
}

export def service-switch [label: string, unit: string]: nothing -> record {
    {
        label: $label
        is-on: {|| unit-active $unit }
        on: {|| ^systemctl --no-ask-password start $unit }
        off: {|| systemctl-guarded stop $unit }
    }
}

# the soft switch alone reads enabled with no card or modem (the -HW field); shared so wifi and mobile cannot drift
export def radio-switch [label: string, radio: string]: nothing -> record {
    let hardware = $"($radio | str uppercase)-HW"
    {
        label: $label
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
