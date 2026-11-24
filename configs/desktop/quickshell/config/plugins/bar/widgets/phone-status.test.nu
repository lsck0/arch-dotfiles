#!/usr/bin/env -S nu --no-config-file
# phone-status.nu's pure parts: which reachable device the widget shows, and the record it gets from the device's
# D-Bus properties, a missing plugin and an absent cellular signal included.
use phone-status.nu [device-choose status-from]

const PHONE = {id: "_phone_", name: "Galaxy S22", type: phone}
const NOTEBOOK = {id: "_notebook_", name: "luca-notebook", type: laptop}
const PLUGINS_ALL = [kdeconnect_battery kdeconnect_findmyphone kdeconnect_ping kdeconnect_share kdeconnect_clipboard kdeconnect_sftp]

def fail [msg: string] { error make {msg: $"phone-status.test: ($msg)"} }

def expect [name: string, actual: any, expected: any] {
    if $actual != $expected { fail $"($name): expected ($expected | to nuon), got ($actual | to nuon)" }
}

def choose-cases [] {
    expect "none" (device-choose []) null
    expect "phone first" (device-choose [$NOTEBOOK $PHONE]) $PHONE
    expect "no phone" (device-choose [$NOTEBOOK]) $NOTEBOOK
}

def status-cases [] {
    let battery = {charge: 44, isCharging: true, hasBattery: true}
    let full = status-from $PHONE $PLUGINS_ALL $battery {cellularNetworkStrength: 3, cellularNetworkType: "5G"} true
    expect "battery" $full.battery 44
    expect "charging" $full.charging true
    expect "signal" $full.signal 3
    expect "network" $full.network "5G"
    expect "mounted" $full.mounted true
    expect "actions" $full.actions {ring: true, ping: true, share: true, clipboard: true, browse: true}

    let bare = status-from $PHONE [kdeconnect_ping] {} {cellularNetworkStrength: -1, cellularNetworkType: ""} false
    expect "no battery" $bare.battery null
    expect "no battery charging" $bare.charging false
    expect "no signal" $bare.signal null
    expect "ping only" $bare.actions {ring: false, ping: true, share: false, clipboard: false, browse: false}

    let empty = status-from $PHONE [] {hasBattery: false, charge: -1, isCharging: false} {} false
    expect "hasBattery false" $empty.battery null
    expect "no report" $empty.signal null
}

def main [] {
    choose-cases
    status-cases
    print "phone-status.test: ok"
}
