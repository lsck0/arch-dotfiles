#!/usr/bin/env -S nu --no-config-file
# forwards ntfy topics from the homelab to desktop notifications

const REPO = path self | path expand | path dirname | path join .. .. ..
use ($REPO | path join scripts lib secrets.nu) [secret-is-plaintext]

const LAB_SCHEMA = 1
# max age of replayed messages
const MAX_REPLAY = 1hr
# keepalive is 45s: under a byte a second over 90s is a dead connection
const IDLE_S = 90
const NO_TOPICS_WAIT = 5min
const BACKOFF_MIN_S = 2
const BACKOFF_MAX_S = 60
# a connection that lived this long was healthy, so the backoff starts over
const HEALTHY = 2min
const ALERT_LINES_MAX = 5
const GLYPH_HOMELAB = "\u{f048d}"
const GLYPH_NTFY = "\u{f009e}"
const NOTIFICATIONS = [
    --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications
    --method org.freedesktop.Notifications.CloseNotification
]

# the homelab's interface for desktop clients, written by its sync.sh (homelab src/modules/lab-export.nix)
def lab-json []: nothing -> path {
    $env.HOMELAB_DIR? | default ($nu.home-dir | path join projects homelab) | path join src generated lab.json
}

def token-file []: nothing -> path {
    $env.NTFY_TOKEN_FILE? | default ($env.DOTFILES? | default $REPO | path join secrets ntfy-desktop-token)
}

def state-dir []: nothing -> path {
    $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state) | path join ntfy-notify
}

# {server, topics} the desktop token reads, or null
def subscription []: nothing -> any {
    let lab = try { open (lab-json) } catch { null }
    if ($lab | describe) !~ '^record' or $lab.schema? != $LAB_SCHEMA or ($lab.ntfy.desktop | is-empty) { return null }
    {server: $lab.ntfy.url, topics: $lab.ntfy.desktop}
}

# "" while the secret is missing or git-crypt locked
def token-read []: nothing -> string {
    if not (secret-is-plaintext (token-file)) { return "" }
    open --raw (token-file) | decode utf-8 | str trim
}

# it reaches xdg-open, so only a plain https link with a host: no file:, custom scheme or option
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

# one alert group's identity across its firing and resolved posts
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

# alert group key -> notification id on screen
def alerts-open-read []: nothing -> record {
    let opened = try { open (state-dir | path join open-alerts.json) } catch { {} }
    if ($opened | describe) =~ '^record' { $opened } else { {} }
}

# the notification's id, or 0 when the server gave none
def notify-send [
    app: string, glyph: string, urgency: string, title: string, body: string, click: string, replaces: int = 0
]: nothing -> int {
    let escaped = $body | str replace --all "&" "&amp;" | str replace --all "<" "&lt;" | str replace --all ">" "&gt;"
    let argv = (
        [-a $app -u $urgency -p -h $"string:omarchy-glyph:($glyph)"]
        ++ (if $replaces != 0 { [-r ($replaces | into string)] } else { [] })
        ++ (if $click != "" { [-h $"string:omarchy-exec-argv:([xdg-open $click] | to json --raw)"] } else { [] })
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
        # no expiry on purpose, critical alerts must not scroll away
        let opened = if $payload.status? == "firing" {
            # a re-firing group replaces its card instead of stacking
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
    let priority = $msg.priority? | default 3 | into int
    let urgency = if $priority >= 5 { "critical" } else if $priority <= 2 { "low" } else { "normal" }
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
    let stream = (^curl --silent --show-error --fail --no-buffer --speed-limit 1 --speed-time $IDLE_S
        --header "User-Agent: ntfy-notify" --header $"Authorization: Bearer ($token)" $url)
    for line in ($stream | lines) {
        let msg = try { $line | from json } catch { null }
        if ($msg | describe) !~ '^record' { continue }
        if $msg.event? != "message" {
            # a quiet hour is not downtime
            if ($last_id | path exists) { touch $last_id }
            # reconnect when the homelab topics change
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
        # re-read each connect so a rotated token needs no restart
        let token = token-read
        if $token == "" {
            # every subscribe would 403, stop instead of retrying
            print --stderr $"ntfy-notify: no token in (token-file)"
            return
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
