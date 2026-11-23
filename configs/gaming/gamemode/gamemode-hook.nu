#!/usr/bin/env -S nu --no-config-file
# gamemode's start/end hook: frees the gpu and cpu from local inference and the trmnl timer while a game runs

const REPO = path self | path expand | path dirname --num-levels 4
use ($REPO | path join scripts lib proc.nu) [succeeds]

const TRMNL_TIMER = "trmnl-claude.timer"
const VLLM_PROXY = "vllm-proxy.service"
const VLLM_SOCKET = "vllm.socket"
const OLLAMA = "ollama.service"
const OLLAMA_SOCKET = "ollama.socket"
const COMFYUI = "comfyui.service"
const COMFYUI_PROXY = "comfyui-proxy.service"
const COMFYUI_SOCKET = "comfyui.socket"
const SPLIT_LOCK_MITIGATE = "/usr/local/bin/split-lock-mitigate"

# Tmpfs like the toggles' volatile state, so a crash mid-game never restores the units after a reboot; vllm.service's
# stop leaves the gpu level to gamemode while gamemode-vllm exists.
def mark [name: string]: nothing -> path {
    $env.XDG_RUNTIME_DIR | path join toggles $"gamemode-($name)"
}

def admin []: nothing -> bool {
    "wheel" in (^id -nG | complete | get stdout | str trim | split row " ")
}

def manager [user: bool]: nothing -> list<string> {
    if $user { [--user --no-ask-password] } else { [--no-ask-password] }
}

# Stops the units, idle sockets included, and records the active ones in mark.
def units-stop [mark: path, units: list<string>, --user]: nothing -> nothing {
    let active = $units | where {|u| succeeds systemctl ...(manager $user) is-active -q $u }
    if ($active | is-empty) { return }
    mkdir ($mark | path dirname)
    $active | str join "\n" | save --force $mark
    # one unit per call: for several, systemctl asks EnqueueUnitJobMany, which systemd's bus policy denies a user
    for u in $units { succeeds systemctl ...(manager $user) stop $u | ignore }
}

# The units units-stop recorded, consuming the mark; none when socket was disabled mid-game (the vllm toggle), so it
# stays down.
def units-recorded [mark: path, socket: string, --user]: nothing -> list<string> {
    if not ($mark | path exists) { return [] }
    let units = open --raw $mark | lines | where $it != ""
    rm $mark
    if (succeeds systemctl ...(manager $user) is-enabled -q $socket) { $units } else { [] }
}

# Socket activation only; the next request brings the service back on demand.
def socket-restore [mark: path, socket: string, --user]: nothing -> nothing {
    if (units-recorded $mark $socket --user=$user | is-not-empty) {
        succeeds systemctl ...(manager $user) start $socket | ignore
    }
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
    units-stop (mark comfyui) [$COMFYUI_SOCKET $COMFYUI_PROXY $COMFYUI] --user
    if (admin) { succeeds pkexec $SPLIT_LOCK_MITIGATE off | ignore }
}

def "main end" []: nothing -> nothing {
    if (succeeds systemctl --user is-enabled -q $TRMNL_TIMER) { succeeds systemctl --user start $TRMNL_TIMER | ignore }
    socket-restore (mark ollama) $OLLAMA_SOCKET
    socket-restore (mark comfyui) $COMFYUI_SOCKET --user
    # --no-block: the proxy's start waits minutes for the model, gamemoded kills a hook after 10s
    for u in (units-recorded (mark vllm) $VLLM_SOCKET) { succeeds systemctl --no-ask-password --no-block start $u | ignore }
    # split lock last: a denied pkexec must not skip the restores above
    if (admin) { succeeds pkexec $SPLIT_LOCK_MITIGATE on | ignore }
}
