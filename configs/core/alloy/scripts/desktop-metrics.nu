#!/usr/bin/nu --no-config-file
# This desktop's health as a textfile for alloy's node exporter (core/alloy), which pushes it to the homelab's desktops
# store. `user` runs as each login and leaves its rows (its dot runs and checks, failed user units) as JSON in its own
# runtime dir; `system` runs as root, adds the system layer's dot runs, AppArmor denials this boot and core dumps, and
# writes the one file alloy reads. Root keeps only USER_METRICS from a login's file and sets its `user` label from the
# file's owner, so no account can forge another's series or the system's. On an offload target root also reads each
# worker user's state in /run/offload/metrics (programming/offload). Names and labels are a contract with the
# homelab's alert rules (l-project-agents, Contracts): a rename is told to homelab first.

const DIR = "/var/lib/node-textfile"
const SYSTEM_RUNS = "/var/lib/dotfiles/runs"
const RUNTIME_ROOT = "/run/user"
const USER_FILE = "desktop-metrics.json"
# a binary under development (a build in a checkout under ~/projects, an agent's scratch copy in /tmp) dies on its own
# asserts as part of the work: its core dumps are no desktop health, so they never page
const DEV_EXE = '^(/tmp/|/var/tmp/|/home/[^/]+/projects/)'
const HELP = {
    dot_run_last_timestamp_seconds: "Unix time the newest dot run of this verb ended"
    dot_run_last_success_timestamp_seconds: "Unix time the newest ok dot run of this verb ended"
    dot_run_last_ok: "1 when the newest dot run of this verb ended ok"
    dot_run_failures: "ERROR records in the newest dot apply or sync"
    dot_check_failed: "dot status checks of this kind at FAIL, pending work left out"
    dot_check_pending: "dot status checks of this kind with work pending (todo: an apply, a package install, a reboot)"
    desktop_failed_units: "Failed units of this systemd manager"
    apparmor_denials_total: "AppArmor denials since boot, by profile"
    desktop_crash_last_timestamp_seconds: "Unix time of the newest core dump of this program in 30 days"
    worker_up: "1 when offload's worker is installed on this desktop"
    jobs_running: "offload jobs running now, every worker user's together"
    job_last_exit: "Exit code of the newest finished offload job of this kind"
    job_last_seconds: "Run time in seconds of the newest finished offload job of this kind"
    job_last_peak_mib: "Peak memory in MiB of the newest finished offload job of this kind"
}
const USER_METRICS = [
    dot_run_last_timestamp_seconds dot_run_last_success_timestamp_seconds dot_run_last_ok dot_run_failures
    dot_check_failed dot_check_pending desktop_failed_units
]
const USER_LABELS = [verb check manager]
# a login's file is a few kilobytes
const USER_FILE_MAX = 1_000_000
# a run log per dot command; the newest are enough for each verb's last outcome
const RUNS_READ = 60
const CRASH_WINDOW = "-30d"
# programming/offload's worker: its entry, and each worker user's state file, named by its uid
const OFFLOAD_RUN = "/run/offload"
const OFFLOAD_METRICS = "/run/offload/metrics"
const OFFLOAD_WORKER = "/usr/local/lib/offload/worker.nu"
const OFFLOAD_KINDS = [static-site oci-image arch-base run]
const OFFLOAD_FILE_MAX = 100_000
# another account's file is read as that uid with no group of its own
const NOBODY_GID = 65534
const READ_TIMEOUT = "5s"

def label-value [value: any]: nothing -> string {
    $value | into string | str replace --all '\' '\\' | str replace --all '"' '\"' | str replace --all "\n" '\n'
}

# rows {name, type, labels: record, value} as exposition text, HELP and TYPE once per name
def exposition []: list<record> -> string {
    $in | group-by name | items {|name, rows|
        let samples = $rows | each {|row|
            let labels = $row.labels | items {|k, v| $'($k)="(label-value $v)"' } | str join ","
            let braces = if ($labels | is-empty) { "" } else { $"{($labels)}" }
            $"($name)($braces) ($row.value)"
        }
        [$"# HELP ($name) ($HELP | get $name)" $"# TYPE ($name) ($rows.0.type)"] ++ $samples | str join "\n"
    } | str join "\n" | $in + "\n"
}

# Replaces path in one rename from a temporary file beside it, so a reader never sees half a file.
def save-atomic [path: path, mode: string]: string -> nothing {
    let text = $in
    let tmp = ^mktemp --tmpdir=($path | path dirname) $".($path | path basename).XXXXXX" | str trim
    $text | save --force $tmp
    ^chmod $mode $tmp
    ^mv --force $tmp $path
}

def metric [name: string, type: string, labels: record, value: any]: nothing -> record {
    {name: $name, type: $type, labels: $labels, value: $value}
}

# One run log as {verb, time, ok, errors}, null while it is still being written. A run that ends through `exit` writes
# no end record for its top span, and root's runs have one top span per stage, so the verb comes from the `run` record
# and ok means: no ERROR or PANIC record, no top span ended other than ok, no failures or install-failures file
# beside the log.
def run-record [file: path, newest: bool]: nothing -> any {
    let records = try { open --raw $file | lines | where $it != "" | each { from json } } catch { return null }
    let run = $records | where kind? == "run" | get --optional 0
    if $run == null { return null }
    let tops = $records | where {|r| $r.kind? == "span" and $r.phase? == "end" and $r.parent? == "" }
    let finished = ($records | any { $in.kind? == "summary" }) or ($tops | is-not-empty)
    # the newest log without a summary or end may be a run in progress; an older one exited early
    if $newest and not $finished { return null }
    let errors = $records | where level? in [ERROR PANIC] | length
    let failed_file = [failures install-failures] | any {|suffix|
        let side = $file | str replace --regex '\.jsonl$' $".($suffix)"
        ($side | path exists) and (open --raw $side | str trim | is-not-empty)
    }
    {
        verb: ($run.target? | default "" | str replace --regex '^system ' '' | split row " " | first)
        time: ($records | last | get time | into datetime | into int | $in // 1_000_000_000)
        ok: ($errors == 0 and not $failed_file and ($tops | all { $in.outcome? == "ok" }))
        errors: $errors
    }
}

# Each verb's last run and last ok run from dot's run logs, and the ERROR records of the newest apply or sync.
def run-metrics [dir: path, layer: string]: nothing -> list<record> {
    if not ($dir | path exists) { return [] }
    let files = ls $dir | where name ends-with ".jsonl" | sort-by name | last $RUNS_READ | get name
    # a read-only run (status, plan) may start during an apply or sync: newest is the newest run that can change things
    let read_only = if ($files | is-empty) { [] } else {
        ^grep --files-with-matches --fixed-strings '"read_only":true' ...$files | complete | get stdout | lines
    }
    let newest = $files | where $it not-in $read_only | last 1
    let runs = $files | each {|file| run-record $file ($file in $newest) } | compact | where verb != ""
    let per_verb = $runs | group-by verb | items {|verb, rows|
        let last = $rows | last
        let last_ok = $rows | where ok | get --optional time | last
        [
            (metric dot_run_last_timestamp_seconds gauge {layer: $layer, verb: $verb} $last.time)
            (metric dot_run_last_ok gauge {layer: $layer, verb: $verb} (if $last.ok { 1 } else { 0 }))
        ] ++ (if $last_ok == null { [] } else {
            [(metric dot_run_last_success_timestamp_seconds gauge {layer: $layer, verb: $verb} $last_ok)]
        })
    } | flatten
    # root's part of a dot apply is its config stage
    let failures = $runs | where verb in [apply sync config] | last 1 | each {|run|
        metric dot_run_failures gauge {layer: $layer} $run.errors
    }
    $per_verb ++ $failures
}

def number [value: any]: nothing -> bool { ($value | describe) in [int float] }

# Another account's file as text, or null: only a regular file uid owns (not followed: the type and owner are the
# file's own), at most max_bytes. Read as uid, bounded in size and time, since the path can be swapped after the stat
# for a link to anything that account may read, or a fifo.
def owned-read [file: path, uid: string, max_bytes: int]: nothing -> any {
    let info = ^stat -c '%u|%F|%s' -- $file | complete | get stdout | str trim | split row "|"
    if ($info | length) != 3 or $info.0 != $uid or $info.1 != "regular file" or ($info.2 | into int) > $max_bytes {
        return null
    }
    let read = (^setpriv $"--reuid=($uid)" $"--regid=($NOBODY_GID)" --clear-groups
        timeout $READ_TIMEOUT head -c ($max_bytes + 1) -- $file | complete)
    # bytes that are not UTF-8 come back as binary, which is no text either
    let text = $read.stdout
    if $read.exit_code != 0 or ($text | describe) != "string" or ($text | str length --utf-8-bytes) > $max_bytes {
        null
    } else { $text }
}

# The rows a login left in its runtime dir: only from a regular file it owns (no link, no fifo), only USER_METRICS with
# numeric values, labels limited to USER_LABELS with scalar values, and `user` set here from the owner. Any other
# shape drops that login's rows, never the run.
def user-rows []: nothing -> list<record> {
    if not ($RUNTIME_ROOT | path exists) { return [] }
    ls $RUNTIME_ROOT | where type == dir | each {|dir|
        let uid = $dir.name | path basename
        let file = $dir.name | path join $USER_FILE
        if not ($uid =~ '^[0-9]+$') or not ($file | path exists) { return [] }
        let login = ^getent passwd $uid | complete | get stdout | split row ":" | get --optional 0 | default ""
        let text = if $login == "" { null } else { owned-read $file $uid $USER_FILE_MAX }
        if $text == null { return [] }
        try {
            let rows = $text | from json
            if ($rows | describe) !~ '^(list|table)' { return [] }
            $rows | where {|r|
                ($r | describe) =~ '^record' and ($r.name? in $USER_METRICS) and (number $r.value?)
            } | each {|r|
                let given = if ($r.labels? | describe) =~ '^record' { $r.labels } else { {} }
                let labels = $given | transpose key value
                    | where {|kv| $kv.key in $USER_LABELS and (($kv.value | describe) in [string int float]) }
                    | reduce --fold {} {|kv, acc| $acc | insert $kv.key ($kv.value | into string) }
                # a login's dot runs are always the user layer; layer="system" is root's alone
                let labels = if ($r.name | str starts-with dot_run_) { $labels | insert layer user } else { $labels }
                metric $r.name gauge ($labels | insert user $login) $r.value
            }
        } catch { [] }
    } | flatten
}

# The worker's rows from each user's state {running, last: {<kind>: {exit, seconds, peakMiB, ended}}}: running summed,
# each kind's newest finished job across users. A malformed state or entry adds nothing.
export def offload-metrics [up: bool, states: list<any>]: nothing -> list<record> {
    let valid = $states | where {|s|
        ($s | describe) =~ '^record' and ($s.running? | describe) == "int" and ($s.last? | describe) =~ '^record'
    }
    let finished = $valid | each {|s| $s.last | transpose kind job } | flatten | where {|e|
        ($e.kind in $OFFLOAD_KINDS and ($e.job | describe) =~ '^record' and ($e.job.exit? | describe) == "int"
            and (number $e.job.seconds?) and (number $e.job.peakMiB?) and (number $e.job.ended?))
    }
    let per_kind = $finished | group-by kind | items {|kind, rows|
        let job = $rows | sort-by { $in.job.ended } | last | get job
        [
            (metric job_last_exit gauge {kind: $kind} $job.exit)
            (metric job_last_seconds gauge {kind: $kind} $job.seconds)
            (metric job_last_peak_mib gauge {kind: $kind} $job.peakMiB)
        ]
    } | flatten
    [
        (metric worker_up gauge {} (if $up { 1 } else { 0 }))
        (metric jobs_running gauge {} ($valid | reduce --fold 0 {|s, acc| $acc + $s.running }))
    ] ++ $per_kind
}

# Each worker user's state file, only a regular one its uid owns; nothing off an offload target.
def offload-rows []: nothing -> list<record> {
    if not ($OFFLOAD_RUN | path exists) { return [] }
    let states = if not ($OFFLOAD_METRICS | path exists) { [] } else {
        ls $OFFLOAD_METRICS | where name =~ '/[0-9]+\.json$' | each {|f|
            let uid = $f.name | path parse | get stem
            try { owned-read $f.name $uid $OFFLOAD_FILE_MAX | from json } catch { null }
        } | compact
    }
    offload-metrics ($OFFLOAD_WORKER | path exists) $states
}

def "main system" []: nothing -> nothing {
    let denied = ^journalctl -k -b --no-pager -o cat --grep 'apparmor="DENIED"' | complete | get stdout | lines
        | each { parse --regex 'profile="(?<profile>[^"]+)"' | get --optional 0.profile } | compact
    let apparmor = $denied | uniq --count | each {|row|
        metric apparmor_denials_total counter {profile: $row.value} $row.count
    }
    let dumps = ^coredumpctl list --json=short --no-pager --since $CRASH_WINDOW | complete
    let crashes = if $dumps.exit_code != 0 { [] } else {
        $dumps.stdout | from json | where exe? != null and $it.exe !~ $DEV_EXE | each {|d| {program: ($d.exe | path basename), time: ($d.time // 1_000_000)} }
            | group-by program | items {|program, rows|
                metric desktop_crash_last_timestamp_seconds gauge {program: $program} ($rows.time | math max)
            }
    }
    let dir = $env.DESKTOP_METRICS_DIR? | default $DIR
    (run-metrics $SYSTEM_RUNS system) ++ $apparmor ++ $crashes ++ (user-rows) ++ (offload-rows) | exposition
    | save-atomic ($dir | path join desktop.prom) "644"
}

def "main user" []: nothing -> nothing {
    # by path: graphviz's dot is on every PATH, and a user unit's may lack ~/.local/bin, where this dot is linked
    let dot = $nu.home-dir | path join .local bin dot
    let status = try { ^$dot status --json | complete | get stdout | from json } catch { null }
    let checks = if $status == null { [] } else {
        # a dot from before the pending field counts its todo rows as failed, as it always did
        $status.checks | default false pending | group-by check | items {|check, rows|
            [
                (metric dot_check_failed gauge {check: $check} ($rows | where level == FAIL and not $it.pending | length))
                (metric dot_check_pending gauge {check: $check} ($rows | where pending | length))
            ]
        } | flatten
    }
    let state = $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state)
    let failed = ^systemctl --user --failed --plain --no-legend | complete | get stdout | lines | where $it != "" | length
    let runtime = $env.XDG_RUNTIME_DIR? | default ($RUNTIME_ROOT | path join (^id -u | str trim))
    (
        (run-metrics ($state | path join dotfiles runs) user)
        ++ $checks
        ++ [(metric desktop_failed_units gauge {manager: user} $failed)]
        | to json --raw
        | save-atomic ($runtime | path join $USER_FILE) "600"
    )
}

def main []: nothing -> nothing { print --stderr "desktop-metrics system|user" ; exit 2 }
