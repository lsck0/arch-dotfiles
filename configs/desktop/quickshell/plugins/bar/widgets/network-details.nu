#!/usr/bin/env -S nu --no-config-file

const SAMPLE = 300ms
const DEVICE_TYPES = [ethernet wifi]

def counters [device: string]: nothing -> record<rx: int, tx: int> {
    let stats = $"/sys/class/net/($device)/statistics"
    {rx: (open $"($stats)/rx_bytes" | into int), tx: (open $"($stats)/tx_bytes" | into int)}
}

def main [] {
    let connectivity = ^nmcli -t -f CONNECTIVITY general | complete | get stdout | str trim | default -e unknown
    let device = ^nmcli -t -f DEVICE,TYPE,STATE dev status
        | lines | split column ":" name type state
        | where state == connected and type in $DEVICE_TYPES
        | get name.0?
    if $device == null {
        {connected: false, connectivity: $connectivity} | to json -r | print
        return
    }

    let show = ^nmcli -t -f GENERAL.CONNECTION,IP4.ADDRESS dev show $device | lines | split column -n 2 ":" key value
    let before = counters $device
    sleep $SAMPLE
    let after = counters $device
    let kbps = {|key| ($after | get $key) - ($before | get $key) | $in / ($SAMPLE / 1sec) / 1024 | math round }
    {
        connected: true
        connectivity: $connectivity
        device: $device
        connection: ($show | where key == GENERAL.CONNECTION | get value.0? | default "")
        ip4: ($show | where key starts-with IP4.ADDRESS | get value.0? | default "")
        mac: (open $"/sys/class/net/($device)/address" | str trim)
        rxKbps: (do $kbps rx)
        txKbps: (do $kbps tx)
    } | to json -r | print
}
