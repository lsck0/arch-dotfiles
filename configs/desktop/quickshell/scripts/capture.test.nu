#!/usr/bin/env -S nu --no-config-file
# capture.nu passes every word through as typed (flags, true, null, numbers) and, on a failure, notifies with the typed
# line; runs against a scratch taskwarrior db and home, with notify-send, quickshell and systemctl stubbed on PATH.

const CAPTURE = path self capture.nu
const STUBS = [notify-send quickshell systemctl systemd-run]

def fail [msg: string] { error make {msg: $"capture.test: ($msg)"} }

def main [] {
    let root = mktemp -d -t capture-test.XXXXXX
    let bin = $root | path join bin
    let log = $root | path join calls.log
    mkdir $bin ($root | path join task) ($root | path join home) ($root | path join run)
    for stub in $STUBS {
        let path = $bin | path join $stub
        $"#!/bin/sh\necho \"($stub) $*\" >> ($log)\n" | save $path
        chmod +x $path
    }
    $"data.location=($root)/task\nnews.version=3.4.1\n" | save ($root | path join taskrc)
    let env_test = {
        PATH: ([$bin] ++ $env.PATH), HOME: ($root | path join home), XDG_RUNTIME_DIR: ($root | path join run)
        TASKRC: ($root | path join taskrc), TASKDATA: ($root | path join task)
    }
    let cases = [
        [words want];
        [[fix the "-v" flag] "fix the -v flag"]
        [["true" story] "true story"]
        [["null" pointer bug] "null pointer bug"]
        [[fix "-Wall" "--help" "0123" "1e3"] "fix -Wall --help 0123 1e3"]
    ]
    try {
        with-env $env_test {
            for c in $cases {
                let r = ^nu $CAPTURE task ...$c.words | complete
                if $r.exit_code != 0 { fail $"task ($c.words | to nuon): ($r.stderr)" }
            }
            let stored = ^task rc.verbose=nothing rc.json.array=on export | from json | get description
            if $stored != ($cases | get want) { fail $"stored ($stored | to nuon)" }

            let r = ^nu $CAPTURE note try --dry-run first | complete
            let inbox = open --raw ($root | path join home sync notes inbox.md)
            if $r.exit_code != 0 or not ($inbox | str contains "try --dry-run first") { fail $"note: ($r.stderr)" }

            let r = ^nu $CAPTURE task due:notadate thing | complete
            if $r.exit_code == 0 or not (open --raw $log | str contains "+ due:notadate thing") { fail "failed task not notified with its line" }
        }
    } catch {|err|
        rm -rf $root
        error make {msg: $err.msg}
    }
    rm -rf $root
}
