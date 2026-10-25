#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run root-run unit-active]

def main [action: string = "toggle", --json] {
    switch-run {
        label: vLLM
        is-on: {|| unit-active vllm.socket }
        on: {||
            if (^systemctl cat vllm.socket | complete).exit_code != 0 {
                error make {msg: "vllm is not installed (configs/llm/vllm)"}
            }
            root-run vllm on
        }
        off: {|| root-run vllm off }
    } $action --json=$json
}
