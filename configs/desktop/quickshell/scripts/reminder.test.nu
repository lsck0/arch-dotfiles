#!/usr/bin/env -S nu --no-config-file
# reminder.nu arms wall-clock timers, keeps a record per reminder and rearms them after a reboot; runs against a scratch
# home, runtime and state dir, with systemd-run and systemctl faked by a units dir and the notifiers stubbed on PATH.

const REMINDER = path self reminder.nu
const CAPTURE = path self capture.nu
const SHELL_TREE = path self ..
const LOGGERS = [notify-send quickshell pw-play]

const SYSTEMD_RUN = '#!/usr/bin/env -S nu --no-config-file
def --wrapped main [...args] {
    let args = $args | each { into string }
    $"systemd-run ($args | str join " ")\n" | save --append ($env.FAKE | path join calls.log)
    if ($env.FAIL_RUN? | default "") == "1" { print -e "Failed to start transient timer unit"; exit 1 }
    let unit = $args | where $it starts-with "--unit=" | first | str replace "--unit=" ""
    let calendar = $args | where $it starts-with "--on-calendar=" | first | str replace "--on-calendar=" ""
    mkdir ($env.FAKE | path join units)
    {unit: $"($unit).timer", activates: $"($unit).service", next: (($calendar | into datetime | into int) // 1000)}
    | to json -r | save -f ($env.FAKE | path join units $"($unit).json")
}
'

const SYSTEMCTL = '#!/usr/bin/env -S nu --no-config-file
def --wrapped main [...args] {
    let args = $args | each { into string }
    let units = $env.FAKE | path join units
    if "list-timers" in $args {
        print (glob ($units | path join *.json) | each { open $in } | to json -r)
    } else if "stop" in $args {
        for timer in ($args | where $it ends-with ".timer") { rm -f ($units | path join ($timer | str replace ".timer" ".json")) }
    } else if "is-active" in $args {
        let timer = $args | where $it ends-with ".timer" | first | str replace ".timer" ".json"
        if not ($units | path join $timer | path exists) { exit 3 }
    }
}
'

def fail [msg: string] { error make {msg: $"reminder.test: ($msg)"} }

def reminder [...args: string]: nothing -> record { ^nu --no-config-file $REMINDER ...$args | complete }

def calls [root: path]: nothing -> string { open --raw ($root | path join fake calls.log) }

def calls-reset [root: path]: nothing -> nothing { "" | save -f ($root | path join fake calls.log) }

def pending [root: path]: nothing -> table { open ($root | path join run quickshell-reminders index.json) | get reminders }

def records [root: path]: nothing -> list<string> {
    glob ($root | path join state quickshell reminders *.json) | each { path parse | get stem }
}

def main [] {
    let root = mktemp -d -t reminder-test.XXXXXX
    let bin = $root | path join bin
    mkdir $bin ($root | path join fake) ($root | path join run) ($root | path join state) ($root | path join home .config)
    ^ln -s $SHELL_TREE ($root | path join home .config quickshell)
    for stub in [[name text]; [systemd-run $SYSTEMD_RUN] [systemctl $SYSTEMCTL]] { $stub.text | save ($bin | path join $stub.name) }
    for logger in $LOGGERS { $"#!/bin/sh\necho \"($logger) $*\" >> \"$FAKE/calls.log\"\n" | save ($bin | path join $logger) }
    for stub in (glob ($bin | path join *)) { chmod +x $stub }
    calls-reset $root
    let env_test = {
        PATH: ([$bin] ++ $env.PATH), HOME: ($root | path join home), XDG_RUNTIME_DIR: ($root | path join run)
        XDG_STATE_HOME: ($root | path join state), FAKE: ($root | path join fake)
    }
    try {
        with-env $env_test {
            let r = reminder 5 tea
            if $r.exit_code != 0 { fail $"set: ($r.stderr)" }
            let armed = calls $root
            if not ($armed =~ '--on-calendar=\d{4}-\d\d-\d\d \d\d:\d\d:\d\d UTC --timer-property=AccuracySec=1s') { fail $"not wall-clock: ($armed)" }
            if ($armed | str contains "--on-active") { fail "monotonic timer armed" }

            if (reminder 1 "--" "--call mom").exit_code != 0 { fail "a message starting with -- not set" }
            if (reminder at (((date now | into int) // 1_000_000_000) + 7200 | into string)).exit_code != 0 { fail "at not set" }
            if (reminder at "5").exit_code == 0 { fail "a past at was set" }
            let labels = pending $root | get label | sort
            if ($labels | length) != 3 or $labels.0 != "--call mom" or not ($labels.1 starts-with "reminder at ") or $labels.2 != "tea" {
                fail $"labels ($labels | to nuon)"
            }
            if (records $root | length) != 3 { fail "records not kept" }

            let tea = pending $root | where label == tea | first | get unit
            if (reminder rename $tea "--" "-5 degrees").exit_code != 0 { fail "rename" }
            if (reminder cancel quickshell-reminder-1m-0).exit_code == 0 { fail "cancel of a missing reminder succeeded" }
            let call = pending $root | where label == "--call mom" | first | get unit
            if (reminder cancel $call).exit_code != 0 or $call in (records $root) { fail "cancel left its record" }

            # a reboot takes the timers and the runtime index; one record has passed while the machine was off
            rm -rf ($root | path join fake units) ($root | path join run quickshell-reminders)
            let missed = "quickshell-reminder-7m-1"
            {unit: $missed, at: 1700000000, message: "laundry"} | to json -r | save ($root | path join state quickshell reminders $"($missed).json")
            calls-reset $root
            if (reminder rearm).exit_code != 0 { fail "rearm" }
            let labels = pending $root | get label | sort
            if ($labels | length) != 3 or "-5 degrees" not-in $labels or "laundry" not-in $labels { fail $"rearmed ($labels | to nuon)" }
            calls-reset $root
            reminder rearm | ignore
            if (calls $root | str contains "systemd-run") { fail "rearm re-armed a running timer" }

            calls-reset $root
            reminder _fire $missed | ignore
            if not (calls $root | str contains '"body":"missed at ') or $missed in (records $root) { fail $"missed fire: (calls $root)" }
            if not (calls $root | str contains "notify-send -a alert -u critical") { fail "fallback not a kept critical alert" }

            let before = records $root
            let r = with-env {FAIL_RUN: "1"} { reminder 3 pizza }
            if $r.exit_code == 0 or (records $root) != $before or not (calls $root | str contains "Reminder not set") { fail "failed arm not reported" }

            let clock = (date now) + 2hr | format date '%H:%M'
            let r = ^nu --no-config-file $CAPTURE remind $clock dentist | complete
            if $r.exit_code != 0 or "dentist" not-in (pending $root | get label) { fail $"capture remind ($clock): ($r.stderr)" }
            let r = ^nu --no-config-file $CAPTURE remind 10min tea | complete
            if $r.exit_code != 0 { fail $"capture remind 10min: ($r.stderr)" }
        }
    } catch {|err|
        rm -rf $root
        error make {msg: $err.msg}
    }
    rm -rf $root
}
