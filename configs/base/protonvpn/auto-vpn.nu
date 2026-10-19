#!/usr/bin/env -S nu --no-config-file
# no connectivity check before a connect: until proton0 is up the system layer keeps the link on tor

const TOGGLE = path self | path expand | path dirname | path join .. .. .. scripts toggles toggle-protonvpn.nu
    | path expand
const HOME_NETWORK = "/run/home-network"
const LINK_TYPES = [ethernet wifi gsm bt]
const MOBILE_TYPES = [gsm bt]
# 70-home-network decides a new link in parallel with nmcli monitor (up to 1 s of arping)
const HOME_WAIT = 3sec
const RETRY_FIRST = 15sec
const RETRY_MAX = 5min
const RETRY_ATTEMPTS = 6
const MONITOR_END = "eof"

def vpn-on []: nothing -> bool {
    (do { ^$TOGGLE get } | complete | get stdout | str trim) == "on"
}

def decide [state: record]: nothing -> record {
    # DEVICE last: a bluetooth one is an address, its escaped colons stay in the remainder
    let links = do { ^nmcli -t -f TYPE,STATE,CON-PATH,DEVICE device } | complete | get stdout | lines
        | parse --regex '^(?<type>[^:]*):(?<state>[^:]*):(?<path>[^:]*):(?<dev>.*)$'
        | where type in $LINK_TYPES and state == connected
    if ($links | is-empty) { return ($state | update retry_at null) }
    let home_links = if ($HOME_NETWORK | path exists) { open --raw $HOME_NETWORK | lines } else { [] }
    # mobile data is never home
    if ($links | all { $in.type not-in $MOBILE_TYPES and $in.dev in $home_links }) {
        # transitions only: a vpn toggled by hand stays as it is until the network changes
        if $state.last != home and (vpn-on) { try { ^$TOGGLE off } }
        return {last: home, attempts: $state.attempts, retry_at: null}
    }
    let net = $links.path | str join " "
    let state = if $state.last != $net { {last: $net, attempts: 0, retry_at: ((date now) + $HOME_WAIT)} } else { $state }
    let due = $state.retry_at == null or (date now) >= $state.retry_at
    if $state.attempts >= $RETRY_ATTEMPTS or not $due { return $state }
    if (vpn-on) or (try { ^$TOGGLE on; true } catch { false }) {
        return ($state | merge {attempts: $RETRY_ATTEMPTS, retry_at: null})
    }
    let attempts = $state.attempts + 1
    let delay = [($RETRY_FIRST * (2 ** ($attempts - 1))) $RETRY_MAX] | math min
    $state | merge {attempts: $attempts, retry_at: (if $attempts < $RETRY_ATTEMPTS { (date now) + $delay })}
}

# nmcli's end ends this, the unit restarts it
def main []: nothing -> nothing {
    job spawn {
        for line in (^nmcli monitor err> /dev/null | lines) { $line | job send 0 }
        $MONITOR_END | job send 0
    } | ignore
    mut state = decide {last: "", attempts: 0, retry_at: null}
    loop {
        let message = if $state.retry_at == null { job recv } else {
            let wait = [($state.retry_at - (date now)) 1sec] | math max
            try { job recv --timeout $wait } catch { null }
        }
        if $message == $MONITOR_END { return }
        $state = decide $state
    }
}
