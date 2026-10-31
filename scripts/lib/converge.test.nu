#!/usr/bin/env -S nu --no-config-file
# Table cases for plan-module, state-write and the ledger diff: pure records in, actions and state records out.
use converge.nu [plan-module state-write state-read ask-batch]
use module.nu [file-text json-merge json-set]
use ledger.nu [ledger-diff ledger-remove ledger-get ledger-set]

const ID = "test/converge"
const TARGET = "/nonexistent/dot-test/file"
const REPO = "/nonexistent/dot-test/repo"
const CONTENT = "one\n"
const CONTENT_OTHER = "two\n"

def fail [msg: string] { error make {msg: $"converge.test: ($msg)"} }

def sha [text: string]: nothing -> string { $text | hash sha256 }

def seen-file [hash: string, mode: string = "644"]: nothing -> record {
    {paths: {$TARGET: {target: $TARGET, type: file, hash: $hash, link: null, mode: $mode}}, units: {}}
}

def seen-none []: nothing -> record {
    {paths: {$TARGET: {target: $TARGET, type: "", hash: null, link: null, mode: null}}, units: {}}
}

def plan-one [decls: list<record>, prev: list<record>, seen: record, recorded: record, force: bool]: nothing -> record {
    plan-module $ID $decls $prev $seen $recorded $REPO $force | first
}

def file-cases []: nothing -> nothing {
    let want = sha $CONTENT
    let other = sha $CONTENT_OTHER
    let decl = file-text $TARGET $CONTENT
    let generated = file-text $TARGET $CONTENT --generated
    let owned = [{kind: file, target: $TARGET, hash: $want}]
    let owned_other = [{kind: file, target: $TARGET, hash: $other}]
    let cases = [
        [name decl prev seen force kind];
        [missing $decl [] (seen-none) false create]
        ["same content, recorded" $decl $owned (seen-file $want) false skip]
        ["same content, unrecorded" $decl [] (seen-file $want) false record]
        ["mode changed" $decl $owned (seen-file $want "600") false update]
        ["mode with leading zero" $decl $owned (seen-file $want "0644") false skip]
        ["changed in the module" $decl $owned_other (seen-file $other) false update]
        ["not the dotfiles' own" $decl [] (seen-file $other) false update]
        [drift $decl $owned (seen-file $other) false drift]
        ["drift, forced" $decl $owned (seen-file $other) true update]
        ["generated drift" $generated $owned (seen-file $other) false update]
    ]
    for c in $cases {
        let a = plan-one [$c.decl] $c.prev $c.seen {} $c.force
        if $a.kind != $c.kind { fail $"file ($c.name): planned ($a.kind) \(($a.reason)\), wants ($c.kind)" }
    }
}

def orphan-cases []: nothing -> nothing {
    let want = sha $CONTENT
    let prev = [{kind: file, target: $TARGET, hash: $want, source: null}]
    let removed = plan-module $ID [] $prev (seen-file $want) {} $REPO false | first
    if $removed.kind != "remove" { fail $"orphan unchanged: planned ($removed.kind), wants remove" }
    let kept = plan-module $ID [] $prev (seen-file (sha $CONTENT_OTHER)) {} $REPO false | first
    if $kept.kind != "drift" { fail $"orphan changed: planned ($kept.kind), wants drift" }
    let claimed = plan-module $ID [] $prev (seen-file $want) {} $REPO false [$TARGET] | first
    if $claimed.kind != "forget" { fail $"orphan claimed: planned ($claimed.kind), wants forget" }
}

def fold-cases [work: path]: nothing -> nothing {
    let file = $work | path join fold.json
    let seen = {paths: {$file: {target: $file, type: "", hash: null, link: null, mode: null}}, units: {}}
    let a = json-merge $file [(json-set [a] 1)] --then ["true"]
    let b = json-merge $file [(json-set [b] 2)] --then ["true"]
    let c = json-merge $file [(json-set [c] 3)] --then ["false"]
    let folded = plan-module $ID [$a $b] [] $seen {} $REPO false
    if ($folded | length) != 1 { fail $"two merges with one --then: ($folded | length) actions, wants 1" }
    if $folded.0.decl.then != ["true"] { fail $"two merges with one --then: then ($folded.0.decl.then | to nuon), wants [true]" }
    if ($folded.0.decl.edits | length) != 2 { fail "two merges: the edits were not folded" }
    let refused = try { plan-module $ID [$a $c] [] $seen {} $REPO false | ignore; false } catch { true }
    if not $refused { fail "two merges with different --then were folded into one command" }
}

def then-failed-cases [work: path]: nothing -> nothing {
    let file = $work | path join hooked.json
    {a: 1} | to json | save --force $file
    let seen = {paths: {$file: {target: $file, type: file, hash: (open --raw $file | sha $in), link: null, mode: "644"}}, units: {}}
    let decl = json-merge $file [(json-set [a] 1)] --then ["true"]
    let clean = plan-module $ID [$decl] [] $seen {} $REPO false | first
    if $clean.kind != "skip" { fail $"merge already applied: planned ($clean.kind), wants skip" }
    let prev = [{kind: json, target: $file, hash: null, at: null, then_failed: true}]
    let retried = plan-module $ID [$decl] $prev $seen {} $REPO false | first
    if $retried.kind != "merge" { fail $"merge whose --then failed: planned ($retried.kind), wants merge" }
}

def state-write-cases [work: path]: nothing -> nothing {
    let file = $work | path join state.json
    let merge = json-merge $file [(json-set [a] 1)] --then ["false"]
    let action = {module: $ID, kind: merge, target: $file, reason: "keys differ", decl: $merge, before: null, after: null}
    let failed = $action | merge {ok: false, error: "exited 1", aside: null, output: "", hash: null, at: null, ms: 0}
    state-write $ID link "input" [$action] [$failed] []
    let after_fail = state-read $ID link
    if $after_fail.input != "" { fail "a failed merge kept the input hash" }
    if not ($after_fail.outputs | get --optional 0.then_failed | default false) { fail "a merge whose --then failed is not marked then_failed" }
    let ok = $failed | merge {ok: true, error: null}
    state-write $ID link "input" [$action] [$ok] $after_fail.outputs
    let after_ok = state-read $ID link
    if ($after_ok.outputs | get --optional 0.then_failed | default false) { fail "a merge whose --then ran keeps then_failed" }

    let decl = file-text $TARGET $CONTENT --mode "600"
    let write = {module: $ID, kind: create, target: $TARGET, reason: missing, decl: $decl, before: null, after: (sha $CONTENT)}
    let done = $write | merge {ok: true, error: null, aside: null, output: "", hash: (sha $CONTENT), at: 1, ms: 0}
    state-write $ID link "input" [$write] [$done] []
    let mode = state-read $ID link | get outputs | where target == $TARGET | get --optional 0.mode
    if $mode != "600" { fail $"a written file records mode ($mode | to nuon), wants \"600\"" }
}

def ledger-diff-cases []: nothing -> nothing {
    let cases = [
        [name owned declared installed keep dropped by_hand];
        ["declared and installed" [a] [a] [a] [] [] []]
        ["dropped, still installed" [a b] [a] [a b] [] [b] []]
        ["dropped, already gone" [a b] [a] [a] [] [] []]
        ["installed by hand" [a] [a] [a c] [] [] [c]]
        ["declared, not yet installed" [] [a] [] [] [] []]
        ["nothing recorded" [] [] [c] [] [] [c]]
        ["kept by hand" [a] [a] [a c d] [c] [] [d]]
        ["kept, dropped" [a b] [a] [a b] [b] [] []]
        ["kept, declared" [a] [a] [a] [a] [] []]
        ["kept, not installed" [] [] [c] [x] [] [c]]
    ]
    for c in $cases {
        let got = ledger-diff $c.owned $c.declared $c.installed $c.keep
        if $got != {dropped: $c.dropped, by_hand: $c.by_hand} { fail $"ledger-diff ($c.name): got ($got | to nuon)" }
    }
    if (ledger-diff [a b] [a] [a b c]) != {dropped: [b], by_hand: [c]} { fail "ledger-diff without keep spares nothing" }
}

# Recorded [a b], declared [a d], installed [a b c]: b is dropped, c installed by hand.
def ledger-remove-cases []: nothing -> nothing {
    let record = {|n| $n | to nuon | save ($env.DOT_TEST_REMOVED) }
    let cases = [
        [name keep yes offer remove ledger removed];
        ["yes removes the dropped, the by hand still ask" [] true true $record [a] [b]]
        ["without the offer the by hand are only listed" [] true false $record [a] [b]]
        ["keep spares the by hand" [c] true true $record [a] [b]]
        ["keep spares the dropped, forgotten" [b] true true $record [a] []]
        ["keep spares both, nothing called" [b c] true true $record [a] []]
        ["no terminal keeps them recorded" [] false true $record [a b] []]
        ["a failed removal keeps them recorded" [] true true {|n| error make {msg: "uninstall failed"} } [a b] []]
    ]
    for c in $cases {
        rm --force $env.DOT_TEST_REMOVED
        ledger-set test [a b]
        ledger-remove test [a d] [a b c] $c.keep $c.yes $c.remove --offer-by-hand=$c.offer
        let got = ledger-get test
        if $got != $c.ledger { fail $"ledger-remove ($c.name): ledger ($got | to nuon), wants ($c.ledger | to nuon)" }
        let removed = if ($env.DOT_TEST_REMOVED | path exists) { open --raw $env.DOT_TEST_REMOVED | from nuon } else { [] }
        if $removed != $c.removed { fail $"ledger-remove ($c.name): removed ($removed | to nuon), wants ($c.removed | to nuon)" }
    }
}

# One call for all paths, its NUL-ended answers in order; a short or failed batch asks each path instead.
def ask-batch-cases []: nothing -> nothing {
    let paths = [/p/one /p/two]
    let each_path = {|p| $"each ($p)" }
    let cases = [
        [name batch wants];
        ["whole batch" {|ps| ^printf 'a\0b\0' } {/p/one: a, /p/two: b}]
        ["short batch" {|ps| ^printf 'a\0' } {/p/one: "each /p/one", /p/two: "each /p/two"}]
        ["failed batch" {|ps| ^sh -c "printf 'a\\0b\\0'; exit 1" } {/p/one: "each /p/one", /p/two: "each /p/two"}]
    ]
    for c in $cases {
        let got = ask-batch $paths $c.batch $each_path
        if $got != $c.wants { fail $"ask-batch ($c.name): got ($got | to nuon), wants ($c.wants | to nuon)" }
    }
    if (ask-batch [] {|ps| ^false } $each_path) != {} { fail "ask-batch: no paths answers something" }
}

def main [] {
    ask-batch-cases
    let work = mktemp --directory
    try {
        with-env {XDG_STATE_HOME: ($work | path join state), DOT_LAYER: user, DOT_RUN_ID: "", DOT_RUN_FILE: "", FAILURES_FILE: ""} {
            file-cases
            orphan-cases
            fold-cases $work
            then-failed-cases $work
            state-write-cases $work
            with-env {DOTFILES_UNATTENDED: "1", DOT_TEST_REMOVED: ($work | path join removed)} {
                ledger-diff-cases
                ledger-remove-cases
            }
        }
    } catch {|e|
        rm --recursive --force $work
        error make {msg: $e.msg}
    }
    rm --recursive --force $work
}
