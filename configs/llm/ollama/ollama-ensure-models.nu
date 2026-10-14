#!/usr/bin/env -S nu --no-config-file
# lazy model provisioning, run on first ollama use, never during an apply; the one source for every ollama model:
# System One and alpaca's default

# each model pinned to the sha256 of its registry manifest, the id `ollama list` shows the first 12 hex of; a pull
# resolves the tag to whatever is current, so the registry is checked before the download and the pulled model after.
# bump by hand: sha256sum of `curl -H 'Accept: <MANIFEST_TYPE>' <REGISTRY>/<name>/manifests/<tag>`
const REGISTRY = "https://registry.ollama.ai/v2/library"
const MANIFEST_TYPE = "application/vnd.docker.distribution.manifest.v2+json"
const OLLAMA_URL = "http://127.0.0.1:11434"
const NIMBLE = {model: "nimble:latest", pin: "6aa3fde96874d5d9f03306e795016e232610aaa5f19efcb107bf9311c712ccd9"}
const LLAMA = {model: "llama3.1:8b", pin: "46e0c10c039e019119339687c3c1757cc81b9da49709a3b3924863ba87ca666e"}
# the typed-decision models behind /v1/systemone
const SYSTEM_ONE_VERSION = "0.35.0"
const LONG_CONTEXT = "llama3.1-64k"
# ollama's default num_ctx is small regardless of the model
const LONG_CONTEXT_TOKENS = 65536
const START_TRIES = 30

def model-digest [model: string]: nothing -> string {
    http get $"($OLLAMA_URL)/api/tags" | get models | where name == $model | get --optional 0.digest | default ""
}

# pulled only when the registry still serves the pin, removed again and failed when what landed is not it
def model-pull-pinned [entry: record]: nothing -> nothing {
    if (model-digest $entry.model) == $entry.pin { return }
    let name = $entry.model | split row ":"
    let manifest = $"($REGISTRY)/($name.0)/manifests/($name.1)"
    let served = http get --raw --headers [Accept $MANIFEST_TYPE] $manifest | hash sha256
    if $served != $entry.pin {
        let why = $"the registry serves ($entry.model) as ($served), pinned ($entry.pin)"
        error make {msg: $"ollama: ($why); not pulling, bump the pin"}
    }
    ^ollama pull $entry.model
    if (model-digest $entry.model) != $entry.pin {
        ^ollama rm $entry.model | ignore
        error make {msg: $"ollama: pulled ($entry.model) does not match its pin ($entry.pin), removed"}
    }
}

def main []: nothing -> nothing {
    if (which ollama | is-empty) { return }
    let version = ^ollama --version o+e>| lines | last | split row " " | last
    let pins = if (^vercmp $version $SYSTEM_ONE_VERSION | into int) < 0 {
        print --stderr $"ollama: ($version) predates System One, not pulling nimble"
        []
    } else { [$NIMBLE] }
    # the first request starts ollama through ollama.socket, the proxy stops it again once idle
    for _ in 1..$START_TRIES {
        if (do { ^ollama list } | complete).exit_code == 0 { break }
        sleep 1sec
    }
    $pins | each { model-pull-pinned $in } | ignore
    if (^ollama list | lines | any { $in starts-with $LONG_CONTEXT }) { return }
    model-pull-pinned $LLAMA
    let modelfile = mktemp --tmpdir
    $"FROM ($LLAMA.model)\nPARAMETER num_ctx ($LONG_CONTEXT_TOKENS)\n" | save --force $modelfile
    ^ollama create $LONG_CONTEXT -f $modelfile
    rm $modelfile
    ^ollama rm $LLAMA.model
}
