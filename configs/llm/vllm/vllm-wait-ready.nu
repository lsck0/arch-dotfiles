#!/usr/bin/nu --no-config-file
# vllm-proxy's ExecStartPre: start vllm on demand and hold the proxy until the backend answers

const BACKEND_URL = "http://127.0.0.1:8001/v1/models"
const READY_TIMEOUT = 10min
const POLL_INTERVAL = 2sec

def main []: nothing -> nothing {
    # the client on :8000 that triggered this start, for journalctl -u vllm-proxy -g vllm-trigger
    let sockets = do { ^ss -Htnp "( sport = :8000 or dport = :8000 )" } | complete | get stdout | lines
    $sockets | where $it !~ systemd-socket-proxyd | each { print --stderr $"vllm-trigger: ($in)" } | ignore
    ^systemctl start vllm.service
    let deadline = (date now) + $READY_TIMEOUT
    while (date now) < $deadline {
        if (try { http get $BACKEND_URL | ignore; true } catch { false }) { return }
        sleep $POLL_INTERVAL
    }
    exit 1
}
