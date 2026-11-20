#!/usr/bin/env -S nu --no-config-file
# offload's consent, the login's half: `ask` (offload-consent.service, started by its path unit on a new request in
# /run/offload/consent) shows each pending request as a notification with Allow once, Always allow this device and
# Deny, and answers in /run/offload/answers; no answer within the request's wait is a deny. "Always" is a trust
# record in /var/lib/offload/trust, which the bar lists and revokes through `offload trust`.

const REPO = path self | path expand | path dirname --num-levels 4
use ($REPO | path join configs programming offload worker.nu) [TRUST_DIR DEVICE CONSENT_WAIT state-at]

const CONSENT_DIR = "/run/offload/consent"
const ANSWER_DIR = "/run/offload/answers"
const GLYPH = "\u{f0c2e}"

def save-atomic [path: path]: string -> nothing {
    let text = $in
    let tmp = ^mktemp --tmpdir=($path | path dirname) $".($path | path basename).XXXXXX" | str trim
    $text | save --force $tmp
    ^chmod 644 $tmp
    ^mv --force $tmp $path
}

# Whether a request file ({device, verb, user, nonce, time}) is one, still waiting and not answered yet.
export def request-pending [request: any, answer: any, now: datetime]: nothing -> bool {
    if ($request | describe) !~ '^record' or not ($request.device? | default "" | into string) =~ $DEVICE { return false }
    let time = try { $request.time | into datetime } catch { return false }
    if $now - $time > $CONSENT_WAIT or $time > $now { return false }
    not (($answer | describe) =~ '^record' and $answer.nonce? == $request.nonce?)
}

# The answer a notification action stands for; always also trusts the device.
export def action-answer [action: string]: nothing -> record<answer: string, trust: bool> {
    match $action {
        "once" => {answer: once, trust: false}
        "always" => {answer: once, trust: true}
        _ => {answer: deny, trust: false}
    }
}

export def trust-list []: nothing -> list<record> {
    let dir = state-at $TRUST_DIR
    if not ($dir | path exists) { return [] }
    glob $"($dir)/*.nuon" | each {|f| try { open $f } catch { null } } | compact
    | where { ($in.device? | default "" | into string) =~ $DEVICE } | sort-by device
}

export def trust-add [device: string]: nothing -> nothing {
    if not ($device =~ $DEVICE) { error make {msg: $"($device) is no device name"} }
    {device: $device, since: (date now)} | to nuon | save-atomic (state-at $TRUST_DIR | path join $"($device).nuon")
}

export def trust-revoke [device: string]: nothing -> nothing {
    if not ($device =~ $DEVICE) { error make {msg: $"($device) is no device name"} }
    rm --force (state-at $TRUST_DIR | path join $"($device).nuon") (state-at $ANSWER_DIR | path join $"($device).nuon")
}

def ask [request: record]: nothing -> nothing {
    let wait_ms = $CONSENT_WAIT / 1ms | into int
    let action = do {
        (^timeout ($CONSENT_WAIT / 1sec | into int) notify-send -a Offload -u critical -t $wait_ms
            -h $"string:lsck0-glyph:($GLYPH)" -A "once=Allow once" -A "always=Always allow this device" -A "deny=Deny"
            $"($request.device) wants to offload work" $"($request.verb) as ($request.user? | default '?')")
    } | complete | get stdout | str trim
    let decided = action-answer $action
    if $decided.trust { trust-add $request.device }
    {nonce: $request.nonce, answer: $decided.answer, time: (date now)} | to nuon
    | save-atomic (state-at $ANSWER_DIR | path join $"($request.device).nuon")
}

# Until no request waits: one arriving while a notification is open is seen on the next pass.
def "main ask" []: nothing -> nothing {
    loop {
        let pending = glob $"(state-at $CONSENT_DIR)/*.nuon" | each {|f|
            let request = try { open $f } catch { null }
            let answer = try { open (state-at $ANSWER_DIR | path join $"($request.device).nuon") } catch { null }
            if (request-pending $request $answer (date now)) { $request }
        } | compact
        if ($pending | is-empty) { return }
        for request in $pending { ask $request }
    }
}

def main []: nothing -> nothing {
    print --stderr "usage: consent.nu ask"
    exit 2
}
