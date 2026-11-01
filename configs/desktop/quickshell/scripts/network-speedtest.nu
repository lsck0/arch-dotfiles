#!/usr/bin/env -S nu --no-config-file
# fast.com throughput in one run, one JSON line each: {name}, {ping} in ms, then {down} and {up} in Mbps once a second

const PROBE = "1.1.1.1"
const PARALLEL = 8
const PHASE_SECONDS = 5
const UPLOAD_MB = 64
const FAST_API_URL = "https://api.fast.com/netflix/speedtest/v2?https=true&token=YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm&urlCount=3"
const CURL_ARGS = [--fail --silent --show-error --connect-timeout 3 --max-time 20 --ipv4 -o /dev/null]

def emit [line: record] {
    print ($line | to json --raw)
}

def fail [message: string] {
    emit {error: $message}
    exit 1
}

# Nu cannot trap TERM, so curl dies with the script through pdeathsig.
def traffic-worker [direction: string, urls: list<string>] {
    mut index = random int 0..<($urls | length)
    loop {
        let url = $urls | get ($index mod ($urls | length))
        if $direction == down {
            ^setpriv --pdeathsig KILL curl ...$CURL_ARGS $url
        } else {
            ^dd if=/dev/zero bs=1M $"count=($UPLOAD_MB)" status=none | ^setpriv --pdeathsig KILL curl ...$CURL_ARGS -X POST --data-binary @- $url
        }
        $index += 1
    }
}

def measure [direction: string, counter: path, urls: list<string>] {
    let workers = 1..$PARALLEL | each { job spawn { traffic-worker $direction $urls } }
    mut before = open $counter | into int
    for _ in 1..$PHASE_SECONDS {
        if (job list | where id in $workers | is-empty) { break }
        sleep 1sec
        let after = open $counter | into int
        emit {$direction: (($after - $before) * 8 / 1_000_000 | math round --precision 1)}
        $before = $after
    }
    job list | where id in $workers | each { job kill $in.id } | ignore
}

def main [] {
    let iface = ^ip -j route get $PROBE | complete | get stdout | from json | get 0?.dev?
    let stats = $"/sys/class/net/($iface)/statistics"
    if $iface == null or not ($stats | path join rx_bytes | path exists) {
        fail "No active network interface"
    }

    let name = ^nmcli -g GENERAL.CONNECTION device show $iface | complete | get stdout | str trim
    emit {name: ($name | default -e $iface)}
    job spawn {
        ^ping -c 1 -W 2 $PROBE | complete | get stdout | parse -r 'time[=<](?<ms>[0-9.]+) ms' | each { emit {ping: ($in.ms | into float)} }
    } | ignore

    let urls = try { http get --max-time 20sec $FAST_API_URL | get targets.url } catch { [] }
    if ($urls | is-empty) {
        fail "Failed to fetch speed test endpoints"
    }
    measure down ($stats | path join rx_bytes) $urls
    measure up ($stats | path join tx_bytes) $urls
}
