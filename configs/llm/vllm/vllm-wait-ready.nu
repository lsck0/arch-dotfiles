#!/usr/bin/nu --no-config-file
const BACKEND_URL = "http://127.0.0.1:8001/v1/models"
const READY_TIMEOUT = 10min
const POLL_INTERVAL = 2sec

def main []: nothing -> nothing {
    let sockets = do { ^ss -Htnp "( sport = :8000 or dport = :8000 )" } | complete | get stdout | lines
    $sockets | where $it !~ systemd-socket-proxyd | each { print --stderr $"vllm-trigger: ($in)" } | ignore
    ^systemctl start vllm.service
    let deadline = (date now) + $READY_TIMEOUT
    while (date now) < $deadline {
        if (try { http get $BACKEND_URL | ignore; true } catch { false }) { return }
        # failed past its start limit: no restart is coming, so the proxy fails now instead of after the timeout
        if (do { ^systemctl is-failed --quiet vllm.service } | complete | get exit_code) == 0 { exit 1 }
        sleep $POLL_INTERVAL
    }
    exit 1
}
