#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run root-run unit-active unit-exists]

# vLLM: get [--json] prints the state, on, off or toggle switches it, a bare call toggles.
def main [action: string = "toggle", --json] {
    switch-run {
        label: vLLM
        available: {|| unit-exists vllm.socket }
        is-on: {|| unit-active vllm.socket }
        on: {||
            if not (unit-exists vllm.socket) {
                error make {msg: "vllm is not installed: dot apply sets it up through llm/vllm, on a ROCm GPU only"}
            }
            root-run vllm on
        }
        off: {|| root-run vllm off }
    } $action --json=$json
}
