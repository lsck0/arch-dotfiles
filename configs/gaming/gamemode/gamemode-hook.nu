#!/usr/bin/env -S nu --no-config-file
# gamemode's [custom] hook: free resources for the game, the ini does the core pinning, visuals stay on

const TRMNL_TIMER = "trmnl-claude.timer"
# local inference holds the whole gpu vram; the socket reactivates vllm on the next client, so only ollama is restored
const VLLM_PROXY = "vllm-proxy.service"
const OLLAMA = "ollama.service"
const SPLIT_LOCK_MITIGATE = "/usr/local/bin/split-lock-mitigate"

# tmpfs like the toggles' volatile state, so a crash mid-game never restores ollama after a reboot
def ollama-mark []: nothing -> path {
    $env.XDG_RUNTIME_DIR | path join toggles gamemode-ollama
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
    ^systemctl --user stop $TRMNL_TIMER
    if (succeeds systemctl is-active -q $VLLM_PROXY) { ^systemctl --no-ask-password stop $VLLM_PROXY }
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
}
