#!/usr/bin/env -S nu --no-config-file
# gamemode's start/end hook: frees the gpu and cpu from local inference and the trmnl timer while a game runs

const TRMNL_TIMER = "trmnl-claude.timer"
const VLLM_PROXY = "vllm-proxy.service"
const OLLAMA = "ollama.service"
const SPLIT_LOCK_MITIGATE = "/usr/local/bin/split-lock-mitigate"

# Tmpfs like the toggles' volatile state, so a crash mid-game never restores ollama after a reboot.
def ollama-mark []: nothing -> path {
    $env.XDG_RUNTIME_DIR | path join toggles gamemode-ollama
}

# vllm.service's stop leaves the gpu level to gamemode while this exists
def vllm-mark []: nothing -> path {
    $env.XDG_RUNTIME_DIR | path join toggles gamemode-vllm
}

def --wrapped succeeds [...argv: string]: nothing -> bool {
    (do { ^$argv.0 ...($argv | skip 1) } | complete).exit_code == 0
}

def admin []: nothing -> bool {
    "wheel" in (^id -nG | split row " ")
}

def main []: nothing -> nothing {
    print --stderr "usage: gamemode-hook start|end"
    exit 2
}

def "main start" []: nothing -> nothing {
    if (succeeds systemctl --user is-enabled -q $TRMNL_TIMER) { ^systemctl --user stop $TRMNL_TIMER }
    if (succeeds systemctl is-active -q $VLLM_PROXY) {
        mkdir (vllm-mark | path dirname)
        touch (vllm-mark)
        ^systemctl --no-ask-password stop $VLLM_PROXY
    }
    if (succeeds systemctl is-active -q $OLLAMA) {
        mkdir (ollama-mark | path dirname)
        touch (ollama-mark)
        ^systemctl --no-ask-password stop $OLLAMA
    }
    if (admin) { ^pkexec $SPLIT_LOCK_MITIGATE off }
}

def "main end" []: nothing -> nothing {
    if (admin) { ^pkexec $SPLIT_LOCK_MITIGATE on }
    if (succeeds systemctl --user is-enabled -q $TRMNL_TIMER) { ^systemctl --user start $TRMNL_TIMER }
    if (ollama-mark | path exists) {
        rm (ollama-mark)
        ^systemctl --no-ask-password start $OLLAMA
    }
    # gamemode restores the level vllm had set, so vllm comes back with it
    if (vllm-mark | path exists) {
        rm (vllm-mark)
        ^systemctl --no-ask-password start $VLLM_PROXY
    }
}
