#!/usr/bin/nu --no-config-file
const BACKEND_URL = "http://127.0.0.1:8189/system_stats"
# below the proxy's TimeoutStartSec, so give-up runs, not systemd's kill
const READY_TIMEOUT = 5min
const POLL_INTERVAL = 2sec

def give-up []: nothing -> nothing {
    print --stderr "comfyui-wait-ready: comfyui.service did not become ready, giving up"
    ^systemctl --user stop comfyui.service
    exit 1
}

# Start comfyui.service for the socket proxy and wait until its backend answers.
def main []: nothing -> nothing {
    # a start refused (its start limit hit) gives up too, not only a backend that never answers
    try { ^systemctl --user start comfyui.service } catch { give-up }
    let deadline = (date now) + $READY_TIMEOUT
    while (date now) < $deadline {
        if (try { http get --max-time 5sec $BACKEND_URL | ignore; true } catch { false }) { return }
        if (do { ^systemctl --user is-failed --quiet comfyui.service } | complete | get exit_code) == 0 { give-up }
        sleep $POLL_INTERVAL
    }
    give-up
}
