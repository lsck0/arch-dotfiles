#!/usr/bin/nu --no-config-file
# A socket proxy's ExecStartPre: starts the backend unit and waits until url answers. On a refused start (its start
# limit hit), a failed unit or the timeout it stops the unit and exits 1: one failed request is one try. The proxy
# still starts and forwards to the dead backend until its idle exit, so only a connection after that window starts
# the unit again. The timeout stays below the proxy's TimeoutStartSec, so this gives up, not systemd's kill.
const POLL_INTERVAL = 2sec
const REQUEST_TIMEOUT = 5sec

def give-up [scope: list<string>, unit: string]: nothing -> nothing {
    print --stderr $"unit-wait-ready: ($unit) did not become ready, giving up"
    ^systemctl ...$scope stop $unit
    exit 1
}

def main [unit: string, url: string, timeout: duration, port: int, --user]: nothing -> nothing {
    let scope = if $user { [--user] } else { [] }
    # who woke the backend: the clients on the socket's port besides the proxy
    let sockets = do { ^ss -Htnp $"\( sport = :($port) or dport = :($port) \)" } | complete | get stdout | lines
    $sockets | where $it !~ systemd-socket-proxyd | each { print --stderr $"unit-wait-ready: ($in)" } | ignore
    try { ^systemctl ...$scope start $unit } catch { give-up $scope $unit }
    let deadline = (date now) + $timeout
    while (date now) < $deadline {
        if (try { http get --max-time $REQUEST_TIMEOUT $url | ignore; true } catch { false }) { return }
        let failed = (do { ^systemctl ...$scope is-failed --quiet $unit } | complete | get exit_code) == 0
        if $failed { give-up $scope $unit }
        sleep $POLL_INTERVAL
    }
    give-up $scope $unit
}
