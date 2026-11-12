#!/usr/bin/env -S nu --no-config-file
# gamemode's start/end hook: frees the gpu and cpu from local inference and the trmnl timer while a game runs

const TRMNL_TIMER = "trmnl-claude.timer"
const VLLM_PROXY = "vllm-proxy.service"
const VLLM_SOCKET = "vllm.socket"
const OLLAMA = "ollama.service"
const OLLAMA_SOCKET = "ollama.socket"
const SPLIT_LOCK_MITIGATE = "/usr/local/bin/split-lock-mitigate"

# Tmpfs like the toggles' volatile state, so a crash mid-game never restores the units after a reboot; vllm.service's
# stop leaves the gpu level to gamemode while gamemode-vllm exists.
def mark [name: string]: nothing -> path {
    $env.XDG_RUNTIME_DIR | path join toggles $"gamemode-($name)"
}

def --wrapped succeeds [...argv: string]: nothing -> bool {
    (do { run-external ...$argv } | complete).exit_code == 0
}

def admin []: nothing -> bool {
    "wheel" in (^id -nG | split row " ")
}

# Stops the units, idle sockets included, and records the active ones in mark.
def units-stop [mark: path, units: list<string>]: nothing -> nothing {
    let active = $units | where {|u| succeeds systemctl is-active -q $u }
    if ($active | is-empty) { return }
    mkdir ($mark | path dirname)
    $active | str join "\n" | save --force $mark
    succeeds systemctl --no-ask-password stop ...$units | ignore
}

# The units units-stop recorded, consuming the mark.
def units-recorded [mark: path]: nothing -> list<string> {
    if not ($mark | path exists) { return [] }
    let units = open --raw $mark | lines | where $it != ""
    rm $mark
    $units
}

def main []: nothing -> nothing {
    print --stderr "usage: gamemode-hook start|end"
    exit 2
}

def "main start" []: nothing -> nothing {
    if (succeeds systemctl --user is-enabled -q $TRMNL_TIMER) { succeeds systemctl --user stop $TRMNL_TIMER | ignore }
    # an idle socket's next request would load the weights onto the gpu mid-game
    units-stop (mark vllm) [$VLLM_SOCKET $VLLM_PROXY]
    units-stop (mark ollama) [$OLLAMA_SOCKET $OLLAMA]
    if (admin) { succeeds pkexec $SPLIT_LOCK_MITIGATE off | ignore }
}

def "main end" []: nothing -> nothing {
    if (succeeds systemctl --user is-enabled -q $TRMNL_TIMER) { succeeds systemctl --user start $TRMNL_TIMER | ignore }
    # a socket disabled mid-game (the vllm toggle) stays down
    let ollama = units-recorded (mark ollama)
    if ($ollama | is-not-empty) and (succeeds systemctl is-enabled -q $OLLAMA_SOCKET) {
        # socket activation only; the next request brings ollama.service back on demand
        succeeds systemctl --no-ask-password start $OLLAMA_SOCKET | ignore
    }
    let vllm = units-recorded (mark vllm)
    if ($vllm | is-not-empty) and (succeeds systemctl is-enabled -q $VLLM_SOCKET) {
        # --no-block: the proxy's start waits minutes for the model, gamemoded kills a hook after 10s
        succeeds systemctl --no-ask-password --no-block start ...$vllm | ignore
    }
    # split lock last: a denied pkexec must not skip the restores above
    if (admin) { succeeds pkexec $SPLIT_LOCK_MITIGATE on | ignore }
}
