# Whether this process can reach the internet: one HTTPS request as the user who would download, its answer kept for
# the run. NetworkManager's connectivity is no answer: its check passes the fail-closed kill switch (fw-egress), which
# lets out only tor, pacman's alpm user and systemd-resolved, so it says full while every user download is dropped.

use state.nu [state-dir save-atomic]
use proc.nu [succeeds]

# where most pinned downloads come from; DOT_NETWORK_PROBE_URL overrides it (a test's file:// or dead port)
const PROBE_URL = "https://github.com"
# a dropped SYN never answers: the connect bound is the probe's cost offline
const PROBE_TIMEOUT_S = 5
const CACHE_FILE = "online.nuon"
const RETRIED = "retried on the next apply"
export const OFFLINE_PENDING = $"offline, ($RETRIED)"
# names over plain DNS, but not over 853: resolved's strict DNS-over-TLS cannot reach its servers
export const DNS_TLS_BLOCKED = "DNS-over-TLS unreachable (port 853 blocked?)"
export const DNS_TLS_PENDING = $"offline, ($DNS_TLS_BLOCKED), ($RETRIED)"
# a captive portal window: plain DNS from the link's own resolver for base/networkmanager.portal_window_s, then strict
# DNS-over-TLS again; core/toggles installs the helper, which takes its caller from pkexec
const PORTAL_HELPER = "/usr/local/bin/toggle-root"
const PORTAL_OPEN = $"pkexec ($PORTAL_HELPER) portal on"
const DOT_PORT = 853
# where a DNS-over-TLS server that also serves DNS-over-HTTPS (quad9) answers: tcp through, only 853 dropped
const HTTPS_PORT = 443
const DNS_PORT = 53
const CONNECT_TIMEOUT_S = 3
# bash's /dev/tcp: one tcp connect, no client of its own needed; $0 the address, $1 the port
const CONNECT = 'exec 3<>"/dev/tcp/$0/$1"'
# one DNS query over tcp ($2, printf escapes, length-prefixed), answered with QR set and RCODE 0 (NOERROR): the server
# and its upstream answer, which a router whose uplink is down does not (SERVFAIL); flags are the reply's bytes 4 and 5
const LOOKUP = 'exec 3<>"/dev/tcp/$0/$1" && printf "$2" >&3 && r=$(head -c 6 <&3 | od -An -tx1 | tr -d " \n") && [ "${#r}" = 12 ] && [ $((0x${r:8:4} & 0x800f)) = $((0x8000)) ]'
# header: id 1, RD, one question; question: type A, class IN
const QUERY_HEADER = 0x[0001 0100 0001 0000 0000 0000]
const QUERY_TAIL = 0x[00 0001 0001]
# a link resolver on this machine (portmaster, a local stub) says nothing about the network
const LOOPBACK = '^(?:127\.|::1$)'
# curl's code for a name it could not resolve, and its text for a lookup cut by its own time bound (28)
const CURL_UNRESOLVED = 6
const CURL_RESOLVE_TIMEOUT = '(?i)resolving timed out'
# a remote that answers 5xx or 429, a name that does not resolve, or a connection that times out: the remote's state,
# not the module's; curl's and git's "returned error", rust's "http status", uv's "status code", wget's "ERROR <code>:",
# go's "context deadline exceeded" (docker), uv's and curl's "timed out", go's "i/o timeout"
const REMOTE_STATUS = '(?:returned error:|http status:|status code:?|ERROR) (?<code>5\d\d|429)\b'
const REMOTE_UNRESOLVED = '(?<code2>could not resolve host|temporary failure in name resolution)'
const REMOTE_TIMEOUT = '(?<code3>context deadline exceeded|operation timed out|connection timed out|i/o timeout)'
const REMOTE_TRANSIENT = $"\(?i\)($REMOTE_STATUS)|($REMOTE_UNRESOLVED)|($REMOTE_TIMEOUT)"

def probe [url: string]: nothing -> record {
    do { ^curl --silent --show-error --head --output /dev/null --connect-timeout $PROBE_TIMEOUT_S --max-time $PROBE_TIMEOUT_S $url } | complete
}

def reachable [address: string, port: int]: nothing -> bool {
    succeeds timeout $CONNECT_TIMEOUT_S bash -c $CONNECT $address $port
}

# name's A query as a tcp DNS message, in printf's \xHH escapes.
def query-escaped [name: string]: nothing -> string {
    let labels = $name | split row "." | each {|l| ($l | str length | into binary | bytes at 0..0) ++ ($l | encode utf8) }
    let message = $labels | reduce --fold $QUERY_HEADER {|l, acc| $acc ++ $l } | $in ++ $QUERY_TAIL
    let length = $message | bytes length | into binary --endian big | bytes at (-2)..
    $length ++ $message | encode hex | split chars | chunks 2 | each { $"\\x($in | str join)" } | str join
}

def answers [address: string]: nothing -> bool {
    let name = $PROBE_URL | url parse | get host
    succeeds timeout $CONNECT_TIMEOUT_S bash -c $LOOKUP $address $DNS_PORT (query-escaped $name)
}

def server-bare []: string -> string { split row "#" | first | split row "%" | first }

# The first DNS server resolved's global section names, without its #name or %interface, null unless that section
# runs strict DNS-over-TLS. status: `resolvectl status`.
export def resolved-tls-server [status: string]: nothing -> any {
    let global = $status | lines | skip until { ($in | str trim) == "Global" } | skip 1 | take while { ($in | str trim) != "" }
        | parse --regex '^\s*(?<key>[^:]+?):\s+(?<value>.*)$'
    let protocols = $global | where key == Protocols | get --optional 0.value | default ""
    if "+DNSOverTLS" not-in ($protocols | split row " ") { return null }
    let current = $global | where key == "Current DNS Server" | get --optional 0.value
    let listed = $global | where key == "DNS Servers" | get --optional 0.value | default "" | split row " " | where $it != ""
    let server = $current | default ($listed | get --optional 0)
    if $server == null { return null }
    $server | server-bare
}

# The DNS servers resolved's link sections name (a link's own, from DHCP), bare, without loopback ones, each once.
# status: `resolvectl status`.
export def resolved-link-servers [status: string]: nothing -> list<string> {
    $status | lines | skip until { $in =~ '^Link \d+ ' }
        | parse --regex '^\s*(?:Current DNS Server|DNS Servers):\s+(?<value>.*)$' | get value
        | each { split row " " } | flatten | where $it != "" | each { server-bare } | where $it !~ $LOOPBACK | uniq
}

# Why a failed probe left this machine offline, as a pending text: DNS_TLS_PENDING when the name did not resolve, the
# resolver runs strict DNS-over-TLS, its server takes no tcp on 853, and the network is up all the same: that server
# takes tcp on 443, or a link's own DNS server answers a lookup over tcp; else OFFLINE_PENDING, which a kill switch or
# a dead link gets. reach: {|address, port| bool}, a tcp connect; answers: {|address| bool}, a lookup there.
export def offline-pending [probe: record, status: string, reach: closure, answers: closure]: nothing -> string {
    let unresolved = $probe.exit_code == $CURL_UNRESOLVED or ($probe.stderr =~ $CURL_RESOLVE_TIMEOUT)
    if not $unresolved { return $OFFLINE_PENDING }
    let server = resolved-tls-server $status
    if $server == null or (do $reach $server $DOT_PORT) { return $OFFLINE_PENDING }
    # each a bounded connect, asked at once: a dropped one costs CONNECT_TIMEOUT_S, not one per server
    let evidence = [{ do $reach $server $HTTPS_PORT }] ++ (resolved-link-servers $status | each {|link| { do $answers $link } })
    if ($evidence | par-each { do $in } | any { $in }) { $DNS_TLS_PENDING } else { $OFFLINE_PENDING }
}

# The way to names on a network that drops 853, for a banner or dot status: {why, command}; --portal adds the captive
# portal window where its helper is installed, else command is null. Strict DNS-over-TLS stays the default; the window
# lifts it on the foreign links only, and only until it ends (or a reboot).
export def dns-tls-escape [--portal]: nothing -> record {
    let why = $"($DNS_TLS_BLOCKED): allow tcp 853 out on this network"
    if not $portal or not ($PORTAL_HELPER | path exists) { return {why: $"($why).", command: null} }
    {why: $"($why), or use plain DNS on this link for a captive portal window and apply within it:", command: $PORTAL_OPEN}
}

# Whether a pending text waits on the network: offline, or a remote's outage (remote-pending).
export def pending-is-network [text: string]: nothing -> bool {
    ($text | str starts-with "offline") or ($text =~ $"^the remote .*, ($RETRIED)$")
}

def check [url: string]: nothing -> record {
    let probed = probe $url
    if $probed.exit_code == 0 { return {online: true, pending: ""} }
    let status = do { ^resolvectl status } | complete | get stdout
    let pending = offline-pending $probed $status {|address, port| reachable $address $port } {|address| answers $address }
    {online: false, pending: $pending}
}

# The pending text for a download's failure the remote caused (an outage, a rate limit, a block of this exit), null
# for any other failure.
export def remote-pending [error: string]: nothing -> any {
    let found = $error | parse --regex $REMOTE_TRANSIENT | get --optional 0
    if $found == null { return null }
    let what = if ($found.code | is-not-empty) {
        $"answered ($found.code)"
    } else if ($found.code3 | is-not-empty) { "timed out" } else { "did not resolve" }
    $"the remote ($what), retried on the next apply"
}

# {online, pending}: pending the text a download waits with while offline, "" online. Asked once per run (DOT_RUN_ID)
# and probe url; outside a run, every call asks.
def network-check []: nothing -> record {
    let url = $env.DOT_NETWORK_PROBE_URL? | default $PROBE_URL
    let run = $env.DOT_RUN_ID? | default ""
    if $run == "" { return (check $url) }
    let cache = state-dir | path join $CACHE_FILE
    let known = try { open $cache } catch { null }
    if $known != null and $known.run? == $run and $known.url? == $url and $known.pending? != null {
        return ($known | select online pending)
    }
    let checked = check $url
    # an unwritable cache only means asking again
    try { {run: $run, url: $url, ...$checked} | to nuon | save-atomic $cache }
    $checked
}

export def network-online []: nothing -> bool { (network-check).online }

# What a download waits with while offline, null online: why, when the probe could tell (DNS_TLS_PENDING), else
# OFFLINE_PENDING.
export def network-offline []: nothing -> any {
    let checked = network-check
    if $checked.online { null } else { $checked.pending }
}
