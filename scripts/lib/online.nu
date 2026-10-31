# Whether this process can reach the internet: one HTTPS request as the user who would download, its answer kept for
# the run. NetworkManager's connectivity is no answer: its check passes the fail-closed kill switch (fw-egress), which
# lets out only tor, pacman's alpm user and systemd-resolved, so it says full while every user download is dropped.

use state.nu [state-dir save-atomic]

# where most pinned downloads come from; DOT_NETWORK_PROBE_URL overrides it (a test's file:// or dead port)
const PROBE_URL = "https://github.com"
# a dropped SYN never answers: the connect bound is the probe's cost offline
const PROBE_TIMEOUT_S = 5
const CACHE_FILE = "online.nuon"
export const OFFLINE_PENDING = "offline, retried on the next apply"
# a remote that answers 5xx or 429, or a name that does not resolve: the remote's state, not the module's; curl's and
# git's "returned error", rust's "http status", uv's "status code", wget's "ERROR <code>:"
const REMOTE_TRANSIENT = '(?i)(?:returned error:|http status:|status code:?|ERROR) (?<code>5\d\d|429)\b|(?<code2>could not resolve host|temporary failure in name resolution)'

def probe [url: string]: nothing -> bool {
    (do { ^curl --silent --head --output /dev/null --connect-timeout $PROBE_TIMEOUT_S --max-time $PROBE_TIMEOUT_S $url } | complete).exit_code == 0
}

# The pending text for a download's failure the remote caused (an outage, a rate limit, a block of this exit), null
# for any other failure.
export def remote-pending [error: string]: nothing -> any {
    let found = $error | parse --regex $REMOTE_TRANSIENT | get --optional 0
    if $found == null { return null }
    let what = if ($found.code | is-not-empty) { $"answered ($found.code)" } else { "did not resolve" }
    $"the remote ($what), retried on the next apply"
}

# Asked once per run (DOT_RUN_ID) and probe url; outside a run, every call asks.
export def network-online []: nothing -> bool {
    let url = $env.DOT_NETWORK_PROBE_URL? | default $PROBE_URL
    let run = $env.DOT_RUN_ID? | default ""
    if $run == "" { return (probe $url) }
    let cache = state-dir | path join $CACHE_FILE
    let known = try { open $cache } catch { null }
    if $known != null and $known.run? == $run and $known.url? == $url { return $known.online }
    let online = probe $url
    # an unwritable cache only means asking again
    try { {run: $run, url: $url, online: $online} | to nuon | save-atomic $cache }
    $online
}
