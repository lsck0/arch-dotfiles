#!/usr/bin/env -S nu --no-config-file
# guarded's crash record: a writing run's crash stays through a read-only run of the same name that goes through
# (`dot internal theme list` after a failed `dot theme`), and the writer's own clean run retires it.
use std/assert

def guarded-run [state: path, name: string, read_only: bool, body: string]: nothing -> nothing {
    let call = $"use cli.nu [guarded]; guarded ($name) --read-only=($read_only) { ($body) }"
    # stdin no terminal: a writing run does not re-exec under the supervisor
    with-env {XDG_STATE_HOME: $state, DOT_NO_JOURNAL: 1} { "" | ^$nu.current-exe --no-config-file -I ($env.FILE_PWD) -c $call | complete } | ignore
}

def crashes [record: path]: nothing -> list<record> {
    if not ($record | path exists) { return [] }
    let crash = open $record
    [($crash | reject --optional others)] ++ ($crash.others? | default [])
}

def read-only-cases [dir: path]: nothing -> nothing {
    let state = $dir | path join state
    let record = $state | path join dotfiles crash.json
    let fail = "^sh -c 'exit 4'"
    guarded-run $state probe false $fail
    assert equal (crashes $record | get command) [probe] "a writing run's crash left no record"
    guarded-run $state probe true "null"
    assert equal (crashes $record | get command) [probe] "a read-only run of the same name retired a writer's crash"
    guarded-run $state probe true $fail
    assert equal (crashes $record | get read_only) [true false] "a read-only crash replaced the writer's of the same name"
    guarded-run $state probe true "null"
    assert equal (crashes $record | get read_only) [false] "a read-only run that went through left its own crash"
    guarded-run $state probe false "null"
    assert not ($record | path exists) "the writer's clean run left its crash record"
}

def main [] {
    let dir = mktemp --directory --tmpdir dot-cli-test-XXXXXX
    try { read-only-cases $dir } catch {|e|
        rm --recursive --force $dir
        error make $e
    }
    rm --recursive --force $dir
}
