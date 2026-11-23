use ../lib/log.nu [log-err]
use ../lib/state.nu [xdg file-trim]
use ../lib/usage.nu [die]

export const TOGGLES_DIR = path self .
export const DOT = path self ../dot.nu
const ROOT_HELPER = "/usr/local/bin/toggle-root"
const ADMIN_GROUP = "wheel"
const IPC_TIMEOUT_S = 3
const TRUSTED_NETWORK = "/run/trusted-network"
const LOCK_BUSY_EXIT = 75

# The state file of a toggle; --volatile puts it on tmpfs, for state whose tool resets on boot (tlp, rfkill ids).
export def state-file [name: string, --volatile]: nothing -> path {
    let dir = if $volatile { xdg runtime toggles } else { xdg state toggles }
    mkdir $dir
    $dir | path join $name
}

# The stored state, "off" when none.
export def state-get [name: string, --volatile]: nothing -> string {
    file-trim (state-file $name --volatile=$volatile) off
}

export def state-set [name: string, value: string, --volatile]: nothing -> nothing {
    $value | save --force (state-file $name --volatile=$volatile)
}

export def state-clear [name: string, --volatile]: nothing -> nothing {
    rm --force (state-file $name --volatile=$volatile)
}

def user-is-admin []: nothing -> bool {
    $ADMIN_GROUP in (^id -nG | complete | get stdout | str trim | split row " ")
}

# Passes a completed external's output on and, when it failed, raises its last stderr line, which the failure toast
# shows: nushell's own error for a failed external names no cause.
def raise-failed [what: string]: record -> nothing {
    let run = $in
    if $run.stdout != "" { print --no-newline $run.stdout }
    if $run.stderr != "" { print --stderr --no-newline $run.stderr }
    if $run.exit_code != 0 {
        let cause = $run.stderr | str trim | lines | last 1 | str join ""
        error make {msg: (if $cause != "" { $cause } else { $"($what) exited ($run.exit_code)" })}
    }
}

# Runs the root helper through pkexec; a non-admin is turned away before its password dialog.
export def root-run [...args: string]: nothing -> nothing {
    if not (user-is-admin) {
        error make {msg: $"refused, this user is not in group ($ADMIN_GROUP): switch it from an admin login"}
    }
    let run = ^pkexec $ROOT_HELPER ...$args | complete
    # 126: the dialog was dismissed; pkexec's own refusals (127) name themselves on stderr
    if $run.exit_code == 126 {
        if $run.stderr != "" { print --stderr --no-newline $run.stderr }
        error make {msg: "authorization cancelled"}
    }
    $run | raise-failed $"toggle-root ($args | str join ' ')"
}

# Runs the calling script again with `args` under its lock, for an n-state toggle (switch-run has its own). The kernel
# drops the lock with the process. A press while a switch runs, or waits on its authentication, is reported and
# dropped with exit 75, never queued behind it.
export def exclusive-run [label: string, ...args: string]: nothing -> nothing {
    let lock = state-file $"($env.CURRENT_FILE | path basename).flock" --volatile
    let code = try {
        ^flock --nonblock --conflict-exit-code $LOCK_BUSY_EXIT $lock nu --no-config-file $env.CURRENT_FILE ...$args
        0
    } catch {|err| $err.exit_code? | default 1 }
    if $code == $LOCK_BUSY_EXIT { notify $label "Still switching" }
    if $code != 0 { exit $code }
}

export def toggle-run [name: string, ...args: string]: nothing -> any {
    ^($TOGGLES_DIR | path join $"toggle-($name).nu") ...$args
}

# A machine without the module has no unit: the toggle is hidden there, not offered and failing.
export def unit-exists [unit: string]: nothing -> bool {
    (^systemctl cat $unit | complete).exit_code == 0
}

export def unit-active [unit: string, --user]: nothing -> bool {
    let scope = if $user { [--user] } else { [] }
    (^systemctl ...$scope is-active --quiet $unit | complete).exit_code == 0
}

# An option's current value, as `dot set --json` reports it.
export def option-value [module: string, key: string]: nothing -> any {
    ^nu --no-config-file $DOT set $module --json | from json | get modules.0.options | where key == $key | get 0.value
}

# The links home-network.nu marked trusted, written by the system layer.
export def trusted-links []: nothing -> list<string> {
    if ($TRUSTED_NETWORK | path exists) { open --raw $TRUSTED_NETWORK | lines } else { [] }
}

# Saved hyprland state is tagged with it, so a restarted compositor never replays the last one's.
export def hyprland-instance []: nothing -> string { $env.HYPRLAND_INSTANCE_SIGNATURE? | default "" }

# Bounded by a timeout, so a shell that is down or hung never blocks a toggle.
export def quickshell-call [target: string, ...args: string]: nothing -> string {
    ^timeout $IPC_TIMEOUT_S quickshell ipc -p (xdg config quickshell) call $target ...$args
}

# Also pings the bar, which refreshes every reader of toggle state, so nothing polls.
# TOGGLES_QUIET=1 (a combined toggle running its parts) keeps the ping and a failure, not the part's own success toast.
export def notify [summary: string, body: string, --critical]: nothing -> nothing {
    quickshell-call toggles changed ($env.PROCESS_PATH | path basename) | complete | ignore
    if not $critical and $env.TOGGLES_QUIET? == "1" { return }
    let urgency = if $critical { [-u critical] } else { [] }
    ^timeout $IPC_TIMEOUT_S notify-send -a toggles ...$urgency $summary $body | complete | ignore
}

# The one failure toast: "Switch to <target> failed, now <state>: <cause>", target and state where they are known.
export def notify-failed [label: string, cause: string, --to: string, --now: string]: nothing -> nothing {
    let to = if $to != null { $" to ($to)" } else { "" }
    let now = if $now != null { $", now ($now)" } else { "" }
    notify $label $"Switch($to) failed($now): ($cause)" --critical
}

# The element after `current` in the input list, wrapping; the first when `current` is not in it.
export def cycle-next [current: any]: list -> any {
    let list = $in
    let index = $list | enumerate | where item == $current | get index.0? | default (-1)
    $list | get (($index + 1) mod ($list | length))
}

# One line and exit 2 for a state an n-state toggle does not have.
export def state-check [what: string, state: string, states: list<string>]: nothing -> nothing {
    if $state not-in $states { die --misuse $"($what) is one of ($states | str join ', ')" }
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

# A flip killed mid-run leaves its lock behind; a system apply (trust network) can run this long.
const LOCK_STALE = 5min

# Taken by creating the dir, which fails when it exists (nushell's own mkdir does not); a stale one is taken over.
def lock-take [lock: path]: nothing -> bool {
    if ($lock | path exists) and ((date now) - (ls --directory $lock | get 0.modified) > $LOCK_STALE) {
        rm --force --recursive $lock
    }
    (^mkdir $lock | complete).exit_code == 0
}

# get/on/off/toggle for a switch; any other action exits 2, a failure exits 1 with its cause in the toast, except a
# `get` that cannot read the state, which reports `error` under the switch's own label. One flip runs at a time: a
# press while one runs is reported, not run again; `on`/`off` in that state already do nothing. An on/off closure may
# return {said: <body>} to replace the "Turned on/off" toast (a change saved but not yet in effect).
export def switch-run [switch: record, action: string, --json]: nothing -> any {
    let available_get = {|| if "available" in $switch { do $switch.available } else { true } }
    let state_get = {|available| if $available and (do $switch.is-on) { "on" } else { "off" } }
    match $action {
        get => {
            let status = try {
                let available = do $available_get
                status-record $switch.label (do $state_get $available) --states [off on] --available=$available
            } catch {
                # a probe that fails cannot say the switch is missing: shown, as an error
                status-record $switch.label error --available=(try { do $available_get } catch { true })
            }
            status-print $status $json
        }
        on | off | toggle => {
            let lock = state-file $"($env.PROCESS_PATH | path basename).lock" --volatile
            if not (lock-take $lock) {
                notify $switch.label "Still switching"
                return
            }
            let fail = {|cause, to|
                rm --force --recursive $lock
                notify-failed $switch.label $cause --to $to
                with-env {LOG_TAG: ($env.PROCESS_PATH | path basename)} { log-err $cause }
                exit 1
            }
            # an explicit on/off whose state cannot be read runs anyway
            let current = try { do $state_get (do $available_get) } catch {|err|
                if $action == toggle { do $fail $"its state cannot be read: ($err.msg)" null }
                null
            }
            if $action == $current {
                rm --force --recursive $lock
                notify $switch.label $"Already ($action)"
                return
            }
            let action = if $action != toggle { $action } else if $current == on { "off" } else { "on" }
            let result = try { do ($switch | get $action) } catch {|err| do $fail $err.msg $action }
            rm --force --recursive $lock
            # anything else it returned is an external's captured stdout, passed on as it would have streamed
            let said = if ($result | describe) =~ '^record' { $result.said? } else {
                if ($result | is-not-empty) { print $result }
                null
            }
            notify $switch.label ($said | default $"Turned ($action)")
        }
        _ => {
            die --misuse $"unknown action '($action)', one of get [--json], on, off, toggle; --help says more"
        }
    }
}

# A system service switched by start and stop. sockets are the ones that activate it: they go with it, or the next
# client starts it again, and one listening counts as on.
export def service-switch [label: string, unit: string, ...sockets: string]: nothing -> record {
    let units = [$unit ...$sockets]
    {
        label: $label
        available: {|| unit-exists $unit }
        is-on: {|| $units | any {|u| unit-active $u } }
        on: {|| ^systemctl --no-ask-password start ...$units | complete | raise-failed $"systemctl start ($unit)" }
        off: {||
            let ask = if (user-is-admin) { [] } else { [--no-ask-password] }
            ^systemctl ...$ask stop ...$units | complete | raise-failed $"systemctl stop ($unit)"
        }
    }
}

# nmcli's answer to a query; a failed one (NetworkManager down) raises its last stderr line, so a probe built on it
# reports `error` rather than a radio off or missing.
export def --wrapped nmcli-read [...args: string]: nothing -> string {
    let run = ^nmcli ...$args | complete
    if $run.exit_code != 0 {
        let cause = $run.stderr | str trim | lines | last 1 | str join ""
        error make {msg: (if $cause != "" { $cause } else { $"nmcli exited ($run.exit_code)" })}
    }
    $run.stdout
}

# A switch for an nmcli radio; on fails without the hardware, which the soft switch alone would report enabled.
export def radio-switch [label: string, radio: string]: nothing -> record {
    let hardware = $"($radio | str uppercase)-HW"
    let types = if $radio == wwan { [gsm wwan] } else { [$radio] }
    {
        label: $label
        available: {|| nmcli-read -t -f TYPE device | lines | any {|type| $type in $types } }
        is-on: {|| (nmcli-read -t -f $"($hardware),($radio | str uppercase)" radio) == "enabled:enabled\n" }
        on: {||
            if (^nmcli -t -f $hardware radio | str trim) != enabled {
                error make {msg: $"no ($radio) hardware"}
            }
            ^nmcli radio $radio on
        }
        off: {|| ^nmcli radio $radio off }
    }
}
