#!/usr/bin/env -S nu --no-config-file
# pulls the pinned models; llm/ollama's link runs it once per pin set where a gpu has vram
const REGISTRY = "https://registry.ollama.ai/v2"
const MANIFEST_TYPE = "application/vnd.docker.distribution.manifest.v2+json"
const MODEL_LAYER_TYPE = "application/vnd.ollama.image.model"
const OLLAMA_URL = "http://127.0.0.1:11434"
# a pin is the sha256sum of `curl -H 'Accept: <MANIFEST_TYPE>' <REGISTRY>/<namespace>/<name>/manifests/<tag>`
# abliterated (uncensored) builds; the 30b moe spills what the gpu lacks into ram and stays fast
export const SMALL = {model: "huihui_ai/qwen3-abliterated:8b", pin: "543f9deff86d8347fd96ea1f3e54e73861ea70d52def71d31ccaeaf013de6ba6"}
export const LARGE = {model: "huihui_ai/qwen3-abliterated:30b-a3b", pin: "45838c4ad5680e5f653edbc60079f29a7ab370d0a5e46a67317945c65e80bd9f"}
# embeddings (rag, semantic search: 4096 dims, 32k context, multilingual) and code (fill-in-the-middle, agentic tool use;
# the same 30b-a3b moe shape as LARGE)
export const EMBEDDING = {model: "qwen3-embedding:8b", pin: "64b933495768fbd3b87c20583d379728a07471e0c66733a9df87cd1901b3c44b"}
export const CODING = {model: "qwen3-coder:30b", pin: "06c1097efce0431c2045fe7b2e5108366e43bee1b4603a7aded8f21689e90bca"}
export const LONG_CONTEXT = "qwen3-abliterated-64k"
export const LONG_CONTEXT_TOKENS = 65536
# a small context for many short parallel requests: ollama gives every parallel slot the full num_ctx, and the openai
# endpoint ignores a per-request num_ctx
export const SHORT_CONTEXT = "qwen3-abliterated-8k"
const SHORT_CONTEXT_TOKENS = 8192
# SMALL with its context fixed, under their own names; SMALL itself is removed once they exist
const CONTEXT_VARIANTS = [[name tokens]; [$LONG_CONTEXT $LONG_CONTEXT_TOKENS] [$SHORT_CONTEXT $SHORT_CONTEXT_TOKENS]]
const START_TRIES = 30

def model-digest [model: string]: nothing -> string {
    http get $"($OLLAMA_URL)/api/tags" | get models | where name == $model | get --optional 0.digest | default ""
}

def manifest-get-pinned [entry: record]: nothing -> record {
    let name = $entry.model | split row ":"
    let repo = if ($name.0 | str contains "/") { $name.0 } else { $"library/($name.0)" }
    let manifest = http get --raw --headers [Accept $MANIFEST_TYPE] $"($REGISTRY)/($repo)/manifests/($name.1)"
    let served = $manifest | hash sha256
    if $served != $entry.pin {
        error make {msg: $"ollama: the registry serves ($entry.model) as ($served), pinned ($entry.pin); not pulling, bump the pin"}
    }
    $manifest | from json
}

def model-pull-pinned [entry: record]: nothing -> nothing {
    if (model-digest $entry.model) == $entry.pin { return }
    manifest-get-pinned $entry | ignore
    ^ollama pull $entry.model
    if (model-digest $entry.model) != $entry.pin {
        ^ollama rm $entry.model | ignore
        error make {msg: $"ollama: pulled ($entry.model) does not match its pin ($entry.pin), removed"}
    }
}

# ollama show prints one `<name> <value>` line per parameter and the base as a `FROM <blob dir>/sha256-<hex>` line,
# and fails for a missing model
def variant-is-current [variant: record, base: string]: nothing -> bool {
    let parameters = do { ^ollama show $variant.name --parameters } | complete
    if $parameters.exit_code != 0 { return false }
    let expected = [num_ctx ($variant.tokens | into string)]
    let from_base = ^ollama show $variant.name --modelfile | lines | any { $in starts-with "FROM " and $in ends-with $base }
    $from_base and ($parameters.stdout | lines | any { ($in | str trim | split row --regex '\s+') == $expected })
}

# a model pulled by hand or left by an older pin set is gone on the next run: the pins are the whole set
def models-prune []: nothing -> nothing {
    let kept = [$LARGE.model $EMBEDDING.model $CODING.model] | append ($CONTEXT_VARIANTS.name | each { $"($in):latest" })
    let stale = http get $"($OLLAMA_URL)/api/tags" | get models | get name | where $it not-in $kept
    for model in $stale {
        print $"ollama: removing unpinned ($model)"
        ^ollama rm $model
    }
}

def context-variants-ensure []: nothing -> nothing {
    let layer = manifest-get-pinned $SMALL | get layers | where mediaType == $MODEL_LAYER_TYPE | get 0.digest
    let base = $"/(($layer | str replace ':' '-'))"
    let missing = $CONTEXT_VARIANTS | where {|v| not (variant-is-current $v $base) }
    if ($missing | is-empty) { return }
    model-pull-pinned $SMALL
    for variant in $missing {
        let modelfile = mktemp --tmpdir
        $"FROM ($SMALL.model)\nPARAMETER num_ctx ($variant.tokens)\n" | save --force $modelfile
        ^ollama create $variant.name -f $modelfile
        rm $modelfile
    }
    ^ollama rm $SMALL.model
}

def main []: nothing -> nothing {
    if (which ollama | is-empty) { return }
    for _ in 1..$START_TRIES {
        if (do { ^ollama list } | complete).exit_code == 0 { break }
        sleep 1sec
    }
    for entry in [$LARGE $EMBEDDING $CODING] { model-pull-pinned $entry }
    context-variants-ensure
    models-prune
}
