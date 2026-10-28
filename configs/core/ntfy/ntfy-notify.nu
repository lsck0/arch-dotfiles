#!/usr/bin/env -S nu --no-config-file
# forwards the homelab's ntfy topics to desktop notifications; lab.json names the topics

const REPO = path self | path expand | path dirname | path join .. .. ..
use ($REPO | path join scripts lib secrets.nu) [secret-is-plaintext]

const LAB_SCHEMA = 1
const MAX_REPLAY = 1hr
# keepalive is 45s: under a byte a second over 90s is a dead connection
const IDLE_S = 90
const NO_TOPICS_WAIT = 5min
const BACKOFF_MIN_S = 2
const BACKOFF_MAX_S = 60
const HEALTHY = 2min
const ALERT_LINES_MAX = 5
const GLYPH_HOMELAB = "\u{f048d}"
const GLYPH_NTFY = "\u{f009e}"
# ntfy's own 1-5 priority scale, 3 the default
const PRIORITY_DEFAULT = 3
const PRIORITY_CRITICAL_MIN = 5
const PRIORITY_LOW_MAX = 2
const NOTIFICATIONS = [
    --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications
    --method org.freedesktop.Notifications.CloseNotification
]

# The homelab's interface for desktop clients, written by its sync.sh (homelab src/modules/lab-export.nix).
def lab-json []: nothing -> path {
    $env.HOMELAB_DIR? | default ($nu.home-dir | path join projects homelab) | path join src generated lab.json
}

def token-file []: nothing -> path {
    $env.NTFY_TOKEN_FILE? | default ($env.DOTFILES? | default $REPO | path join configs secrets keys ntfy-desktop-token)
}

def state-dir []: nothing -> path {
    $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state) | path join ntfy-notify
}

def subscription []: nothing -> any {
    let lab = try { open (lab-json) } catch { null }
    if ($lab | describe) !~ '^record' or $lab.schema? != $LAB_SCHEMA or ($lab.ntfy.desktop | is-empty) { return null }
    {server: $lab.ntfy.url, topics: $lab.ntfy.desktop}
}

def token-read []: nothing -> string {
    if not (secret-is-plaintext (token-file)) { return "" }
    open --raw (token-file) | decode utf-8 | str trim
}

# The url when it is a plain https link, else empty: it reaches xdg-open, so no file:, custom scheme or option.
def https [url: any]: nothing -> string {
    if ($url | describe) != string or not ($url starts-with "https://") or $url =~ '[\s\x00-\x1f]' { return "" }
    let host = try { $url | url parse | get host } catch { "" }
    if $host == "" { "" } else { $url }
}

def alert-summary [payload: record]: nothing -> record {
    let alerts = $payload.alerts
    let firing = $payload.status? == "firing"
    let names = $alerts | each {|a| $a.labels?.alertname? | default alert } | uniq | sort
    let state = if $firing { "firing" } else { "resolved" }
    let lines = $alerts | first $ALERT_LINES_MAX
        | each {|a| $a.annotations?.summary? | default ($a.labels?.instance? | default "") }
    {
        title: (if ($names | length) == 1 { $"($names.0) ($state)" } else { $"($alerts | length) alerts ($state)" })
        body: ($lines | where $it != "" | str join "\n")
        urgency: (if $firing and ($alerts | any { $in.labels?.severity? == critical }) { "critical" } else { "normal" })
        click: ($alerts | each {|a| https $a.generatorURL? } | where $it != "" | get --optional 0 | default "")
    }
}

def group-key [payload: record]: nothing -> string {
    let key = $payload.groupKey?
    if ($key | describe) == string and $key != "" { return $key }
    $payload.alerts | each {|a| $"($a.labels?.alertname? | default alert)@($a.labels?.instance? | default '')" }
        | sort | str join "|"
}

def file-replace [file: path, text: string]: nothing -> nothing {
    mkdir (state-dir)
    $text | save --force $"($file).tmp"
    mv --force $"($file).tmp" $file
}

def alerts-open-read []: nothing -> record {
    let opened = try { open (state-dir | path join open-alerts.json) } catch { {} }
    if ($opened | describe) =~ '^record' { $opened } else { {} }
}

def notify-send [
    app: string, glyph: string, urgency: string, title: string, body: string, click: string, replaces: int = 0
]: nothing -> int {
    let escaped = $body | str replace --all "&" "&amp;" | str replace --all "<" "&lt;" | str replace --all ">" "&gt;"
    let argv = (
        [-a $app -u $urgency -p -h $"string:lsck0-glyph:($glyph)"]
        ++ (if $replaces != 0 { [-r ($replaces | into string)] } else { [] })
        ++ (if $click != "" { [-h $"string:lsck0-exec-argv:([xdg-open $click] | to json --raw)"] } else { [] })
        ++ [$title $escaped]
    )
    try { do { ^notify-send ...$argv } | complete | get stdout | str trim | into int } catch { 0 }
}

def notify [msg: record]: nothing -> nothing {
    let text = $msg.message? | default ""
    let payload = try { $text | from json } catch { null }
    if ($payload | describe) =~ '^record' and ($payload.alerts? | describe) =~ '^(list|table)' {
        let s = alert-summary $payload
        let key = group-key $payload
        let opened = alerts-open-read
        let previous = $opened | get --optional $key | default 0
        let opened = $opened | reject --optional $key
        let opened = if $payload.status? == "firing" {
            let id = notify-send Homelab $GLYPH_HOMELAB $s.urgency $s.title $s.body $s.click $previous
            if $id != 0 { $opened | insert $key $id } else { $opened }
        } else {
            if $previous != 0 { do { ^gdbus call ...$NOTIFICATIONS ($previous | into string) } | complete | ignore }
            notify-send Homelab $GLYPH_HOMELAB normal $s.title $s.body $s.click | ignore
            $opened
        }
        file-replace (state-dir | path join open-alerts.json) ($opened | to json --raw)
        return
    }
    let priority = $msg.priority? | default $PRIORITY_DEFAULT | into int
    let urgency = if $priority >= $PRIORITY_CRITICAL_MIN { "critical" } else if $priority <= $PRIORITY_LOW_MAX { "low" } else { "normal" }
    let title = $msg.title? | default ($msg.topic? | default ntfy)
    notify-send ntfy $GLYPH_NTFY $urgency $title $text (https $msg.click?) | ignore
}

def last-id-read []: nothing -> string {
    let file = state-dir | path join last-id
    if not ($file | path exists) or (ls $file | get 0.modified) < ((date now) - $MAX_REPLAY) { return "" }
    open --raw $file | str trim
}

def subscribe [sub: record, since: string, token: string]: nothing -> nothing {
    let query = if $since == "" { "" } else { $"?({since: $since} | url build-query)" }
    let url = $"($sub.server)/($sub.topics | each { url encode } | str join ',')/json($query)"
    let last_id = state-dir | path join last-id
    # the token goes to curl on stdin: on the command line every local user could read it with ps
    # iterate the stream directly: a `let` would collect the whole response first, so nothing shows until curl exits
    for line in ($"Authorization: Bearer ($token)\n" | ^curl --silent --show-error --fail --no-buffer --speed-limit 1
        --speed-time $IDLE_S --header "User-Agent: ntfy-notify" --header @- $url | lines) {
        let msg = try { $line | from json } catch { null }
        if ($msg | describe) !~ '^record' { continue }
        if $msg.event? != "message" {
            if ($last_id | path exists) { touch $last_id }
            if (subscription) != $sub { return }
            continue
        }
        if (date now) - (($msg.time? | default 0) * 1_000_000_000 | into datetime) < $MAX_REPLAY { notify $msg }
        file-replace $last_id ($msg.id? | default "")
    }
}

def main []: nothing -> nothing {
    mut delay_s = $BACKOFF_MIN_S
    loop {
        let started = date now
        let token = token-read
        if $token == "" {
            print --stderr $"ntfy-notify: no token in (token-file), waiting"
            sleep $NO_TOPICS_WAIT
            continue
        }
        let sub = subscription
        if $sub == null {
            print --stderr $"ntfy-notify: no ntfy topics in (lab-json)"
            sleep $NO_TOPICS_WAIT
            continue
        }
        try { subscribe $sub (last-id-read) $token } catch {|e| print --stderr $"ntfy-notify: ($e.msg)" }
        $delay_s = if (date now) - $started > $HEALTHY { $BACKOFF_MIN_S } else {
            [($delay_s * 2) $BACKOFF_MAX_S] | math min
        }
        sleep ($delay_s * 1sec)
    }
}
