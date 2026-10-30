#!/usr/bin/env -S nu --no-config-file
# pulls the pinned models when run by hand; dot apply never downloads models
const REGISTRY = "https://registry.ollama.ai/v2"
const MANIFEST_TYPE = "application/vnd.docker.distribution.manifest.v2+json"
const OLLAMA_URL = "http://127.0.0.1:11434"
# a pin is the sha256sum of `curl -H 'Accept: <MANIFEST_TYPE>' <REGISTRY>/<namespace>/<name>/manifests/<tag>`
# abliterated (uncensored) builds; the 30b moe spills what the gpu lacks into ram and stays fast
const SMALL = {model: "huihui_ai/qwen3-abliterated:8b", pin: "543f9deff86d8347fd96ea1f3e54e73861ea70d52def71d31ccaeaf013de6ba6"}
const LARGE = {model: "huihui_ai/qwen3-abliterated:30b-a3b", pin: "45838c4ad5680e5f653edbc60079f29a7ab370d0a5e46a67317945c65e80bd9f"}
export const LONG_CONTEXT = "qwen3-abliterated-64k"
export const LONG_CONTEXT_TOKENS = 65536
const START_TRIES = 30

def model-digest [model: string]: nothing -> string {
    http get $"($OLLAMA_URL)/api/tags" | get models | where name == $model | get --optional 0.digest | default ""
}

def model-pull-pinned [entry: record]: nothing -> nothing {
    if (model-digest $entry.model) == $entry.pin { return }
    let name = $entry.model | split row ":"
    let repo = if ($name.0 | str contains "/") { $name.0 } else { $"library/($name.0)" }
    let manifest = $"($REGISTRY)/($repo)/manifests/($name.1)"
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
    for _ in 1..$START_TRIES {
        if (do { ^ollama list } | complete).exit_code == 0 { break }
        sleep 1sec
    }
    model-pull-pinned $LARGE
    if (^ollama list | lines | any { $in starts-with $LONG_CONTEXT }) { return }
    model-pull-pinned $SMALL
    let modelfile = mktemp --tmpdir
    $"FROM ($SMALL.model)\nPARAMETER num_ctx ($LONG_CONTEXT_TOKENS)\n" | save --force $modelfile
    ^ollama create $LONG_CONTEXT -f $modelfile
    rm $modelfile
    ^ollama rm $SMALL.model
}
