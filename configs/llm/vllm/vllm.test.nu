#!/usr/bin/env -S nu --no-config-file
# prefix-root-owned on a missing dir, a dir the test user owns and a root-owned tree; on a ROCm machine, system's
# prefix-own and keyed venv steps.

use mod.nu [prefix-root-owned system]

const HERE = path self .
const ROOT_OWNED = "/usr/share/licenses"
const CFG = {
    model: m, model_revision: r, tool_call_parser: hermes, reasoning_parser: qwen3, gpu_memory_utilization: 0.5
    kv_cache_dtype: fp8
}

def fail [msg: string] { error make {msg: $"vllm.test: ($msg)"} }

def main [] {
    let dir = mktemp --directory --tmpdir dot-vllm-test-XXXXXX
    let cases = [[name dir want]; ["missing dir" ($dir | path join missing) false] ["user-owned dir" $dir false]
        ["root-owned tree" $ROOT_OWNED true]]
    let failed = $cases | where {|c| (prefix-root-owned $c.dir) != $c.want }
    rm --recursive $dir
    for c in $failed { print --stderr $"vllm.test: ($c.name): got (not $c.want)" }
    if ($failed | is-not-empty) { fail $"($failed | length) of ($cases | length) prefix-root-owned cases failed" }

    # system reads the venv's sources relative to the module dir, as converge runs it
    cd $HERE
    let steps = system $CFG | where kind == step
    if ($steps | is-empty) {
        print --stderr "vllm.test: system skipped: no ROCm GPU"
        return
    }
    if ($steps.target | take 2) != [prefix-own venv] { fail $"steps start ($steps.target | take 2), want prefix-own venv" }
    let venv = $steps | where target == venv | first
    if $venv.creates != "/opt/vllm/venv/bin/python" { fail $"venv creates ($venv.creates)" }
    if ($venv.key | str length) != 64 { fail $"venv key ($venv.key) is not a sha256" }
}
