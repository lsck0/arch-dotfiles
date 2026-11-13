#!/usr/bin/env -S nu --no-config-file

const REPO = path self ../../..
const TOGGLES = $REPO | path join scripts toggles
use ($REPO | path join scripts lib state.nu) [xdg]
# not ipapi.co: it 429ed about every second keyless request
const LOOKUP_URL = "https://ipinfo.io/json"
const LOOKUP_TIMEOUT = 8sec
const RETRY_DELAY = 5sec
const HOME_DISPATCHER = "/etc/NetworkManager/dispatcher.d/70-home-network"
const TRUSTED_NETWORK = "/run/trusted-network"
const ZONEINFO = "/usr/share/zoneinfo"
const TZ_SHAPE = '^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+){1,2}$'

def disabled-flag []: nothing -> path {
    xdg state toggles timezone-auto-disabled
}

def tz-current []: nothing -> string {
    do { ^timedatectl show -p Timezone --value } | complete | get stdout | str trim
}

# The tunnel carrying traffic, null for none; an unknown state counts as up, so nothing geolocates through an exit.
def tunnel-up []: nothing -> any {
    let get = {|name| do { ^($TOGGLES | path join $"toggle-($name).nu") get } | complete | get stdout | str trim }
    let route = do $get route
    if $route not-in [direct offline] { return (if $route == "" { "route?" } else { $route }) }
    if (do $get vpn) != off { return vpn }
    null
}

def off-trusted []: nothing -> bool {
    ($HOME_DISPATCHER | path exists) and not (($TRUSTED_NETWORK | path exists) and (open --raw $TRUSTED_NETWORK | is-not-empty))
}

def tz-valid [tz: string]: nothing -> bool {
    ($tz =~ $TZ_SHAPE) and (($ZONEINFO | path join $tz | path expand | path type) == file)
}

def lookup []: nothing -> any {
    try { http get --full --allow-errors --max-time $LOOKUP_TIMEOUT $LOOKUP_URL } catch { null }
}

def tz-detect []: nothing -> any {
    let first = lookup
    let response = if $first != null and ($first.status == 429 or $first.status >= 500) {
        sleep $RETRY_DELAY
        lookup
    } else { $first }
    if $response == null { return null }
    let tz = if ($response.body | describe) =~ '^record' { $response.body.timezone? | default "" } else { "" }
    if $tz == "" { error make {msg: $"timezone-auto: ipinfo.io answered HTTP ($response.status) without a timezone"} }
    $tz
}

# Why detection is skipped, null when it may run: nothing reaches ipinfo.io unless the answer could be used.
def suppressed []: nothing -> any {
    if (disabled-flag | path exists) { return "disabled" }
    if (off-trusted) { return "off a trusted network" }
    let tunnel = tunnel-up
    if $tunnel != null { return $"tunnel ($tunnel)" }
    if "wheel" not-in (^id -nG | str trim | split row " ") { return "not in wheel" }
    null
}

def apply []: nothing -> nothing {
    if (suppressed) != null { return }
    let current = tz-current
    let want = tz-detect
    if $want == null or not (tz-valid $want) or $want == $current { return }
    ^timedatectl --no-ask-password set-timezone $want
    if (which notify-send | is-not-empty) {
        do { ^notify-send -a timezone "Timezone updated" $"($current) -> ($want)" } | complete | ignore
    }
    do { ^systemctl --user try-restart quickshell.service } | complete | ignore
}

def main []: nothing -> nothing { apply }

def "main apply" []: nothing -> nothing { apply }

def "main status" []: nothing -> nothing {
    let reason = suppressed
    let detected = if $reason != null { $"\(($reason), no lookup\)" } else {
        try { tz-detect | default "(unavailable)" } catch { "(unavailable)" }
    }
    print $"current:  (tz-current)"
    print $"auto:     (if (disabled-flag | path exists) { 'disabled' } else { 'enabled' })"
    print $"detected: ($detected)"
}

def "main enable" []: nothing -> nothing {
    rm --force (disabled-flag)
    print "timezone auto-detection enabled"
}

def "main disable" []: nothing -> nothing {
    mkdir (disabled-flag | path dirname)
    touch (disabled-flag)
    print "timezone auto-detection disabled"
}
