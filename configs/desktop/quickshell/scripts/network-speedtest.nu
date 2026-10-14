#!/usr/bin/env -S nu --no-config-file
# fast.com throughput in one run: "name <connection>", "ping <ms>", then "down <Mbps>" and "up <Mbps>" once a second

const PROBE = "1.1.1.1"
const PARALLEL = 8
const PHASE_SECONDS = 5
const UPLOAD_MB = 64
const FAST_API_URL = "https://api.fast.com/netflix/speedtest/v2?https=true&token=YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm&urlCount=3"
const CURL_ARGS = [--fail --silent --show-error --connect-timeout 3 --max-time 20 --ipv4 -o /dev/null]

def rate-format [value: float]: nothing -> string {
    if $value <= 0 { "0.0" } else if $value < 10 { $value | into string -d 1 } else { $value | math round | into string }
}

# round-robin from a random start to spread load across fast.com nodes; nu cannot trap TERM, so curl dies with the
# script through pdeathsig instead of an exit trap
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
        print $"($direction) (rate-format (($after - $before) * 8 / 1_000_000))"
        $before = $after
    }
    job list | where id in $workers | each { job kill $in.id } | ignore
}

def main [] {
    let iface = ^ip -j route get $PROBE | complete | get stdout | from json | get 0?.dev?
    let stats = $"/sys/class/net/($iface)/statistics"
    if $iface == null or not ($stats | path join rx_bytes | path exists) {
        print -e "No active network interface"
        exit 1
    }

    let name = ^nmcli -g GENERAL.CONNECTION device show $iface | complete | get stdout | str trim
    print $"name ($name | default -e $iface)"
    job spawn {
        ^ping -c 1 -W 2 $PROBE | complete | get stdout | parse -r 'time[=<](?<ms>[0-9.]+) ms' | each { print $"ping ($in.ms)" }
    } | ignore

    let urls = try { http get --max-time 20sec $FAST_API_URL | get targets.url } catch { [] }
    if ($urls | is-empty) {
        print -e "Failed to fetch speed test endpoints"
        exit 1
    }
    measure down ($stats | path join rx_bytes) $urls
    measure up ($stats | path join tx_bytes) $urls
}
