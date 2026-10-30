#!/usr/bin/nu --no-config-file
const BACKEND_URL = "http://127.0.0.1:8001/v1/models"
# below the proxy's TimeoutStartSec, so give-up runs, not systemd's kill
const READY_TIMEOUT = 9min
const POLL_INTERVAL = 2sec

# Stops vllm: one failed request is one try. The proxy still starts and forwards to the dead backend until its idle
# exit, so only a connection after that window reloads the weights.
def give-up []: nothing -> nothing {
    print --stderr "vllm-wait-ready: vllm.service did not become ready, giving up"
    ^systemctl stop vllm.service
    exit 1
}

# Start vllm.service for the socket proxy and wait until its backend answers.
def main []: nothing -> nothing {
    let sockets = do { ^ss -Htnp "( sport = :8000 or dport = :8000 )" } | complete | get stdout | lines
    $sockets | where $it !~ systemd-socket-proxyd | each { print --stderr $"vllm-wait-ready: ($in)" } | ignore
    ^systemctl start vllm.service
    let deadline = (date now) + $READY_TIMEOUT
    while (date now) < $deadline {
        if (try { http get $BACKEND_URL | ignore; true } catch { false }) { return }
        if (do { ^systemctl is-failed --quiet vllm.service } | complete | get exit_code) == 0 { give-up }
        sleep $POLL_INTERVAL
    }
    give-up
}
