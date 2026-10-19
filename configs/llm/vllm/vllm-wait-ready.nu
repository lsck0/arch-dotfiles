#!/usr/bin/nu --no-config-file
const BACKEND_URL = "http://127.0.0.1:8001/v1/models"
# below the proxy's TimeoutStartSec, so the give-up path runs, not systemd's kill
const READY_TIMEOUT = 9min
const POLL_INTERVAL = 2sec

def main []: nothing -> nothing {
    let sockets = do { ^ss -Htnp "( sport = :8000 or dport = :8000 )" } | complete | get stdout | lines
    $sockets | where $it !~ systemd-socket-proxyd | each { print --stderr $"vllm-trigger: ($in)" } | ignore
    ^systemctl start vllm.service
    let deadline = (date now) + $READY_TIMEOUT
    while (date now) < $deadline {
        if (try { http get $BACKEND_URL | ignore; true } catch { false }) { return }
        # failed past its start limit: no restart is coming, so give up now instead of after the timeout
        if (do { ^systemctl is-failed --quiet vllm.service } | complete | get exit_code) == 0 { give-up }
        sleep $POLL_INTERVAL
    }
    give-up
}

# one failed request is one try: no more restarts that reload the weights until the next connection
def give-up []: nothing -> nothing {
    print --stderr "vllm-trigger: vllm.service did not become ready, giving up"
    ^systemctl stop vllm.service
    exit 1
}
