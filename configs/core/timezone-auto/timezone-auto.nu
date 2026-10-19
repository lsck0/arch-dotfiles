#!/usr/bin/env -S nu --no-config-file

const TOGGLES = path self | path expand | path dirname | path join .. .. .. scripts toggles | path expand
const TUNNELS = [vpn protonvpn tor]
# one https provider, the lookup leaks our ip; not ipapi.co: it 429ed about every second keyless request
const LOOKUP_URL = "https://ipinfo.io/json"
const LOOKUP_TIMEOUT = 8sec
const RETRY_DELAY = 5sec
const HOME_DISPATCHER = "/etc/NetworkManager/dispatcher.d/70-home-network"
const HOME_NETWORK = "/run/home-network"
const ZONEINFO = "/usr/share/zoneinfo"
const TZ_SHAPE = '^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+){1,2}$'

def disabled-flag []: nothing -> path {
    $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state) | path join toggles timezone-auto-disabled
}

def tz-current []: nothing -> string {
    do { ^timedatectl show -p Timezone --value } | complete | get stdout | str trim
}

# the tunnel carrying traffic, null for none; fail closed: an unknown tunnel state never geolocates through an exit
def tunnel-up []: nothing -> any {
    for t in $TUNNELS {
        let toggle = $TOGGLES | path join $"toggle-($t).nu"
        if not ($toggle | path exists) { return $"($t)?" }
        if (do { ^$toggle get } | complete | get stdout | str trim) == "on" { return $t }
    }
    null
}

def off-home []: nothing -> bool {
    ($HOME_DISPATCHER | path exists) and not (($HOME_NETWORK | path exists) and (open --raw $HOME_NETWORK | is-not-empty))
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

def apply [dry_run: bool]: nothing -> nothing {
    if (disabled-flag | path exists) or (off-home) or (tunnel-up) != null { return }
    let current = tz-current
    let want = tz-detect
    if $want == null or not (tz-valid $want) or $want == $current or $dry_run { return }
    # the machine's clock is an admin's to set (49-timezone-auto.rules); a background unit never asks anyone else
    if "wheel" not-in (^id -nG | str trim | split row " ") { return }
    ^timedatectl --no-ask-password set-timezone $want
    if (which notify-send | is-not-empty) {
        do { ^notify-send -a Timezone "Timezone updated" $"($current) -> ($want)" } | complete | ignore
    }
    do { ^systemctl --user try-restart quickshell.service } | complete | ignore
}

def main []: nothing -> nothing { apply false }

def "main apply" []: nothing -> nothing { apply false }

def "main check" []: nothing -> nothing { apply true }

def "main status" []: nothing -> nothing {
    let tunnel = tunnel-up
    let detected = if (off-home) { "(off home, no lookup)" } else {
        try { tz-detect | default "(unavailable)" } catch { "(unavailable)" }
    }
    print $"current:  (tz-current)"
    print (if $tunnel == null { "tunnel:   none" } else { $"tunnel:   ($tunnel) \(detection suppressed\)" })
    print (if (disabled-flag | path exists) { "auto:     disabled" } else { "auto:     enabled" })
    print $"detected: ($detected)"
}

def "main enable" []: nothing -> nothing {
    mkdir (disabled-flag | path dirname)
    rm --force (disabled-flag)
    print "timezone auto-detection enabled"
}

def "main disable" []: nothing -> nothing {
    mkdir (disabled-flag | path dirname)
    touch (disabled-flag)
    print "timezone auto-detection disabled"
}
