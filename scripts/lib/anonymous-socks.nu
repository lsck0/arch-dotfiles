# scoped SOCKS anonymiser: a private tor instance whose pool of ports each verifiably exits through tor, its own
# packets wearing an os persona, everything in anonsocks.slice guarded to lo

const CONFIG = ".config/anonymous-socks/config"
# 9061 and 9161 clear of a system tor's 9050/9051; new streams reuse a circuit this long (tor's default), then rotate
const DEFAULTS = {
    PORT: 9061, RATE: 0, TOR_BIN: tor, POOL_SIZE: 10, CONTROL_PORT: 9161, MAX_CIRCUIT_DIRTINESS: 600, PERSONA: 1
    PERSONA_OS: windows, TOR_CHECK_URL: "https://check.torproject.org/api/ip"
}
# tor runs as its own user unit, so its cgroup scopes the persona to exactly the proxied traffic
const TOR_UNIT = "anonymous-socks-tor.service"
const SLICE = "anonsocks.slice"
const ISOLATION = "IsolateSOCKSAuth IsolateDestAddr IsolateDestPort"
# the netfilter half runs as root through configs/core/toggles' toggle-root, which polkit lets the bar call unprompted
const TOGGLE_ROOT = "/usr/local/bin/toggle-root"
const PERSONA_TTL = {windows: 128, macos: 64, ios: 64, linux: 64, android: 64}
const PC_READ_TIMEOUT_MS = 15000
const PC_CONNECT_TIMEOUT_MS = 8000
const CHECK_TIMEOUT_S = "15"
const CONTROL_TIMEOUT_S = "5"
# tor builds a circuit before the first request can exit
const BOOTSTRAP_TIMEOUT = 60sec
const BOOTSTRAP_POLL = 2sec

def runtime [name: string]: nothing -> path {
    $env.XDG_RUNTIME_DIR? | default $"/run/user/(^id -u | str trim)" | path join $name
}

# defaults < ANONYMOUS_SOCKS_* in the environment < the config file
def settings []: nothing -> record {
    let file = $env.ANONYMOUS_SOCKS_CONF? | default ($nu.home-dir | path join $CONFIG)
    let from_env = $DEFAULTS | columns | reduce --fold {} {|k, acc|
        let v = $env | get --optional $"ANONYMOUS_SOCKS_($k)"
        if $v == null { $acc } else { $acc | insert $k $v }
    }
    let from_file = if ($file | path exists) {
        open --raw $file | lines | each { split row "#" | first | str trim }
        | parse --regex '^ANONYMOUS_SOCKS_(?<k>\w+)=(?<v>.*)$'
        | reduce --fold {} {|r, acc| $acc | upsert $r.k ($r.v | str trim --char '"') }
    } else { {} }
    let s = $DEFAULTS | merge $from_env | merge $from_file
    let datadir = $env.ANONYMOUS_SOCKS_TOR_DATADIR? | default (runtime anonymous-socks-tor)
    $s | merge {
        PORT: ($s.PORT | into int), RATE: ($s.RATE | into int), POOL_SIZE: ($s.POOL_SIZE | into int)
        PERSONA: ($s.PERSONA | into string), DATADIR: $datadir
        PC_CONF: ($env.ANONYMOUS_SOCKS_PROXYCHAINS_CONF? | default (runtime anonymous-socks-proxychains.conf))
        VERIFIED: (runtime anonymous-socks.verified)
    }
}

def pool-ports [s: record]: nothing -> list<int> { 0..<$s.POOL_SIZE | each { $s.PORT + $in } }

def err [text: string]: nothing -> nothing { print -e $"anonymous-socks: ($text)" }

# up only when every pool port listens, and only as our tor unit's own pid: a listener another local user planted on a
# pool port would otherwise be handed every proxied connection
def is-up [s: record]: nothing -> bool {
    let pid = do { ^systemctl --user show -p MainPID --value $TOR_UNIT } | complete | get stdout | str trim
    if not ($pid =~ '^[1-9][0-9]*$') { return false }
    let listeners = ^ss -tlnpH | lines | parse --regex '^\S+\s+\S+\s+\S+\s+\S*:(?<port>\d+)\s+\S+\s*(?<proc>.*)$'
        | update port { into int }
    # any other listener on a port marks it foreign for good
    pool-ports $s | all {|p|
        let on = $listeners | where port == $p
        ($on | is-not-empty) and ($on | all { $in.proc | str contains $"pid=($pid)," })
    }
}

# never a password prompt, the toggle runs it from the bar: a non-admin is refused before pkexec reaches polkit
def root-netfilter [...args: string]: nothing -> nothing {
    if not (^id -nG | split row " " | any { $in == wheel }) { error make {msg: "the netfilter guard needs an admin"} }
    ^pkexec $TOGGLE_ROOT anonsocks ...$args
}

# cap how fast tools may open new SOCKS sessions; its own nft table, never the firewall's
def rate-on [s: record]: nothing -> nothing {
    if $s.RATE <= 0 { return }
    if (which nft | is-empty) { return (err "nft missing, running without rate cap") }
    root-netfilter rate-on ($s.PORT | into string) ($s.POOL_SIZE | into string) ($s.RATE | into string)
}

# ttl/hop limit set only on packets whose socket lives in tor's cgroup
def persona-on [s: record]: nothing -> nothing {
    if $s.PERSONA != "1" { return }
    let ttl = $PERSONA_TTL | get --optional $s.PERSONA_OS
    if $ttl == null { return (err $"unknown persona '($s.PERSONA_OS)', persona off") }
    let cgroup = ^systemctl --user show --property=ControlGroup --value $TOR_UNIT | str trim
        | str trim --left --char "/"
    if $cgroup == "" { return (err $"no cgroup for ($TOR_UNIT), persona off") }
    root-netfilter persona-on ($ttl | into string) $cgroup
}

# one pool port reachable and leaving through a tor exit; false on any doubt, so a gating caller fails closed
def check-port [s: record, port: int]: nothing -> bool {
    let proxy = $"127.0.0.1:($port)"
    let got = do { ^curl -fsS --max-time $CHECK_TIMEOUT_S --socks5-hostname $proxy $s.TOR_CHECK_URL } | complete
    if $got.exit_code != 0 { err $"no route to ($s.TOR_CHECK_URL) through :($port)"; return false }
    let body = try { $got.stdout | from json } catch { {} }
    if ($body.IsTor? | default false) != true {
        err $":($port) exit is not a Tor node: fail closed \(($got.stdout | str trim)\)"
        return false
    }
    print $"anonymous-socks ok: :($port) tor exit ($body.IP? | default unknown)"
    true
}

def check-all [s: record]: nothing -> bool {
    if not (is-up $s) { err $"tunnel down on 127.0.0.1:($s.PORT)"; return false }
    pool-ports $s | par-each { check-port $s $in } | all { $in }
}

# every port up and on a tor exit; an error when not
export def anonymous-socks-check []: nothing -> nothing {
    if not (check-all (settings)) { error make {msg: "anonymous-socks: check failed"} }
}

# a [ProxyList] spanning the pool; with round_robin and chain_len 1 each connection exits on the next port
export def anonymous-socks-proxylist []: nothing -> string {
    ["[ProxyList]"] ++ (pool-ports (settings) | each { $"socks5 127.0.0.1 ($in)" }) | str join "\n" | $"($in)\n"
}

# the whole proxychains config for the live pool, regenerated on up so it always matches the pool size
export def anonymous-socks-proxyconf []: nothing -> string {
    [
        ("# generated by anonymous-socks on up, regenerated each time, do not edit by hand; round_robin + chain_len 1: "
            + "one proxy per connection, so requests spread across the pool")
        round_robin "chain_len = 1" proxy_dns
        $"tcp_read_time_out ($PC_READ_TIMEOUT_MS)" $"tcp_connect_time_out ($PC_CONNECT_TIMEOUT_MS)"
    ] | str join "\n" | $"($in)\n(anonymous-socks-proxylist)"
}

export def anonymous-socks-down []: nothing -> nothing {
    let s = settings
    # kills what still runs in the slice before the guard goes, so nothing continues unguarded
    do { ^systemctl --user stop $SLICE } | complete | ignore
    try { root-netfilter nft-off } catch { }
    try { root-netfilter persona-off } catch { }
    rm --force $s.PC_CONF $s.VERIFIED
    do { ^systemctl --user stop $TOR_UNIT } | complete | ignore
}

def start [s: record]: nothing -> nothing {
    # proxychains' LD_PRELOAD misses static binaries, raw sockets and udp, so anything in the slice may only talk to lo
    try {
        ^systemctl --user start $SLICE
        root-netfilter egress-on
    } catch { error make {msg: "egress guard failed, not starting"} }
    mkdir $s.DATADIR
    chmod 700 $s.DATADIR
    # one SocksPort per slot, each its own SessionGroup plus Isolate* flags: independent per-destination circuits
    let socks = pool-ports $s | enumerate
        | each { [--SocksPort $"127.0.0.1:($in.item) ($ISOLATION) SessionGroup=($in.index)"] }
        | flatten
    # never /etc/tor/torrc: its User directive would force a root start and break this unprivileged instance
    (^systemd-run --user --quiet --collect $"--unit=($TOR_UNIT)" (which $s.TOR_BIN | get 0.path)
        -f ($s.DATADIR | path join torrc) --ignore-missing-torrc
        --defaults-torrc ($s.DATADIR | path join torrc-defaults) --ignore-missing-torrc
        --RunAsDaemon 0 ...$socks --ControlPort $"127.0.0.1:($s.CONTROL_PORT)" --CookieAuthentication 1
        --MaxCircuitDirtiness ($s.MAX_CIRCUIT_DIRTINESS | into string) --DataDirectory $s.DATADIR --Log "notice stderr")
    rate-on $s
    persona-on $s
    let deadline = (date now) + $BOOTSTRAP_TIMEOUT
    while not (check-all $s) {
        if (date now) >= $deadline { error make {msg: $"verification failed after ($BOOTSTRAP_TIMEOUT), tearing down"} }
        sleep $BOOTSTRAP_POLL
    }
    anonymous-socks-proxyconf | save --force $s.PC_CONF
    touch $s.VERIFIED
}

export def anonymous-socks-up []: nothing -> nothing {
    let s = settings
    if (which $s.TOR_BIN | is-empty) {
        error make {msg: "tor not found (set ANONYMOUS_SOCKS_TOR_BIN or: sudo pacman -S tor)"}
    }
    if ($s.VERIFIED | path exists) and (is-up $s) { return (err "already up") }
    # a tor left from an interrupted or failed up was never verified, and its guards may be missing: start over
    if (do { ^systemctl --user -q is-active $TOR_UNIT } | complete).exit_code == 0 {
        err "unverified instance running, restarting it"
        anonymous-socks-down
    }
    rm --force $s.VERIFIED
    # any failure before the verify tears it all down, so nothing stays up unverified
    try { start $s } catch {|e| anonymous-socks-down; error make {msg: $e.msg} }
    print $"anonymous-socks up: ($s.POOL_SIZE) ports, round-robin config at ($s.PC_CONF)"
}

# no tor round trip: that took 24s and blocked the toggle menu
export def anonymous-socks-status []: nothing -> string {
    let s = settings
    if ($s.VERIFIED | path exists) and (is-up $s) { "on" } else { "off" }
}

# fresh circuits for new streams: SIGNAL NEWNYM on the control port, cookie auth
export def anonymous-socks-newnym []: nothing -> nothing {
    let s = settings
    if not (is-up $s) { error make {msg: "tunnel down"} }
    let cookie = $s.DATADIR | path join control_auth_cookie
    if not ($cookie | path exists) { error make {msg: $"control cookie unreadable at ($cookie)"} }
    let hex = open --raw $cookie | into binary | encode hex | str lowercase
    let replies = $"AUTHENTICATE ($hex)\r\nSIGNAL NEWNYM\r\nQUIT\r\n"
        | do { ^curl -sS --max-time $CONTROL_TIMEOUT_S $"telnet://127.0.0.1:($s.CONTROL_PORT)" } | complete
    if $replies.exit_code != 0 { error make {msg: $"no control port on :($s.CONTROL_PORT)"} }
    # one reply per command: AUTHENTICATE, then SIGNAL
    let lines = $replies.stdout | lines
    if ($lines | first 2 | length) == 2 and ($lines | first 2 | all { str starts-with "250" }) {
        print "newnym: fresh circuits requested"
    } else {
        error make {msg: $"newnym: control refused \(($lines | first 2 | str join ' ')\)"}
    }
}
