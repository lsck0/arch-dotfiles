#!/usr/bin/env -S nu --no-config-file
# on means vllm.socket listens and cold-starts the server on the first request; off also frees the vram
use lib.nu [switch-run root-run unit-active]

def main [action: string = "toggle"] {
    switch-run {
        label: vLLM
        is-on: {|| unit-active vllm.socket }
        on: {||
            # configs/llm/vllm installs the units only once its venv builds; say so instead of systemd's "does not exist"
            if (^systemctl cat vllm.socket | complete).exit_code != 0 {
                error make {msg: "vllm is not installed (configs/llm/vllm)"}
            }
            root-run vllm on
        }
        off: {|| root-run vllm off }
    } $action
}
