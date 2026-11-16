#!/usr/bin/env -S nu --no-config-file
# Only the pinned models stay: the prune keeps the pins and the context variants and removes everything else, SMALL
# (the variants' base) included. A pull happens only for a manifest whose sha256 is the pin, and a pull that lands
# another digest is removed. ollama is a stub logging its argv; the registry and the local digest are injected.

use ollama-ensure-models.nu [SMALL LARGE EMBEDDING CODING LONG_CONTEXT SHORT_CONTEXT models-stale manifest-pinned pull-pinned]

const MANIFEST = '{"schemaVersion":2,"layers":[]}'

def fail [msg: string] { error make {msg: $"ollama.test: ($msg)"} }

def prune-cases []: nothing -> nothing {
    let installed = [
        $LARGE.model $EMBEDDING.model $CODING.model $"($LONG_CONTEXT):latest" $"($SHORT_CONTEXT):latest"
        $SMALL.model "llama3:8b" $"($LARGE.model)-old" "qwen3-coder:latest"
    ]
    let got = models-stale $installed
    let want = [$SMALL.model "llama3:8b" $"($LARGE.model)-old" "qwen3-coder:latest"]
    if $got != $want { fail $"stale ($got | to nuon), want ($want | to nuon)" }
    if (models-stale [$LARGE.model $CODING.model] | is-not-empty) { fail "a pinned model counted as stale" }
}

# One pull-pinned run in dir: the local digest before and after the stub's pull, the registry's manifest text.
def pull [dir: path, entry: record, before: string, after: string, served: string]: nothing -> record {
    let calls = $dir | path join calls
    let digest = $dir | path join digest
    rm --force $calls
    $before | save --force $digest
    let run = with-env {PATH: ([($dir | path join bin)] ++ $env.PATH), STUB_DIGEST: $after, STUB_DIR: $dir} {
        try {
            pull-pinned $entry {|m| open --raw $digest } {|e| manifest-pinned $e $served | ignore }
            null
        } catch {|e| $e.msg }
    }
    {error: $run, calls: (if ($calls | path exists) { open --raw $calls | lines } else { [] })}
}

def pull-cases []: nothing -> nothing {
    let dir = mktemp --directory --tmpdir dot-ollama-test-XXXXXX
    let bin = $dir | path join bin
    mkdir $bin
    let stub = '#!/bin/sh
echo "$*" >> "$STUB_DIR/calls"
[ "$1" = pull ] && printf %s "$STUB_DIGEST" > "$STUB_DIR/digest"
exit 0
'
    $stub | save ($bin | path join ollama)
    chmod +x ($bin | path join ollama)
    let entry = {model: "test/model:8b", pin: ($MANIFEST | hash sha256)}
    let other = $'($MANIFEST) '
    let cases = [
        [what before after served calls fails];
        ["already the pin" $entry.pin $entry.pin $other [] false]
        ["pinned manifest, pull lands the pin" "" $entry.pin $MANIFEST [$"pull ($entry.model)"] false]
        ["registry serves another manifest" "" $entry.pin $other [] true]
        ["an older local copy, registry moved on" "sha256:old" $entry.pin $other [] true]
        ["pull lands another digest" "" "sha256:other" $MANIFEST [$"pull ($entry.model)" $"rm ($entry.model)"] true]
    ]
    for c in $cases {
        let r = pull $dir $entry $c.before $c.after $c.served
        if $r.calls != $c.calls { rm --recursive --force $dir; fail $"($c.what): ollama ran ($r.calls | to nuon), want ($c.calls | to nuon)" }
        if ($r.error != null) != $c.fails { rm --recursive --force $dir; fail $"($c.what): error ($r.error | to nuon)" }
    }
    rm --recursive --force $dir
}

def main [] {
    prune-cases
    pull-cases
}
