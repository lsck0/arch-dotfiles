#!/usr/bin/env bash
# Scoped SOCKS anonymiser: a private Tor instance on 9061, every listed port verified to exit through it.
set -euo pipefail

CONF="${ANONYMOUS_SOCKS_CONF:-$HOME/.config/anonymous-socks/config}"
# shellcheck disable=SC1090
[ -r "$CONF" ] && source "$CONF"

# own Tor instance; 9061 not Tor's default 9050 to avoid colliding with a system tor. Must match proxychains.conf
PORT="${ANONYMOUS_SOCKS_PORT:-9061}"
RATE="${ANONYMOUS_SOCKS_RATE:-0}"                 # max new SOCKS connections/sec, 0 = uncapped
TOR_BIN="${ANONYMOUS_SOCKS_TOR_BIN:-tor}"
DATADIR="${ANONYMOUS_SOCKS_TOR_DATADIR:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/anonymous-socks-tor}"
# tor runs as its own user unit, so its cgroup scopes the persona to exactly the proxied traffic
TOR_UNIT="anonymous-socks-tor.service"
# exists only after up verified every port exits through Tor
VERIFIED="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/anonymous-socks.verified"

# circuit pool: one Tor daemon, POOL_SIZE SocksPorts each in its own SessionGroup so circuits never overlap
POOL_SIZE="${ANONYMOUS_SOCKS_POOL_SIZE:-10}"

# control port for SIGNAL NEWNYM, cookie auth; 9161 clear of the pool and Tor's default 9051
CTRL_PORT="${ANONYMOUS_SOCKS_CONTROL_PORT:-9161}"
COOKIE="$DATADIR/control_auth_cookie"

# new streams reuse a circuit up to this long (Tor default 600), then get a fresh exit
MAX_DIRTINESS_S="${ANONYMOUS_SOCKS_MAX_CIRCUIT_DIRTINESS:-600}"

# runtime proxychains config, regenerated on up to match the live pool
PC_CONF="${ANONYMOUS_SOCKS_PROXYCHAINS_CONF:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/anonymous-socks-proxychains.conf}"
PC_READ_TIMEOUT_MS=15000
PC_CONNECT_TIMEOUT_MS=8000

# pool ports, low to high; PORT is the base and index 0
pool_ports() { local i; for ((i = 0; i < POOL_SIZE; i++)); do echo $((PORT + i)); done; }

# os persona on tor's own packets only: the wire to the guards looks like PERSONA_OS, nothing else on the machine changes
PERSONA="${ANONYMOUS_SOCKS_PERSONA:-1}"              # 0 = disable
PERSONA_OS="${ANONYMOUS_SOCKS_PERSONA_OS:-windows}"  # windows, macos, ios, linux, android

# Tor Project's exit check; verifying against it proves traffic left via a Tor exit (exit IP rotates per circuit)
TOR_CHECK_URL="${ANONYMOUS_SOCKS_TOR_CHECK_URL:-https://check.torproject.org/api/ip}"

# Tor builds a circuit before the first request can exit; poll check() this long after start
BOOTSTRAP_TIMEOUT_S=60
BOOTSTRAP_POLL_S=2

err() { echo "anonymous-socks: $*" >&2; }

# Up only when every pool port is listening, so a half-started daemon reads down.
is_up() {
    local p l
    l=$(ss -tlnH 2>/dev/null) || return 1
    for p in $(pool_ports); do [[ $l == *":$p "* ]] || return 1; done
}

# refuse to start if tor is missing, naming the install command, rather than half-starting
require_tor() {
    command -v "$TOR_BIN" >/dev/null || {
        err "tor not found (set ANONYMOUS_SOCKS_TOR_BIN or: sudo pacman -S tor)"
        exit 1
    }
}

# cap how fast tools may open new SOCKS sessions; own nft table, never touches the firewall's inet fw table
rate_on() {
    [ "$RATE" -gt 0 ] 2>/dev/null || return 0
    command -v nft >/dev/null || {
        err "nft missing, running without rate cap"
        return 0
    }
    sudo nft -f - <<NFT
table inet anonymous_socks {
    chain out {
        type filter hook output priority 0; policy accept;
        oif "lo" tcp dport $PORT-$((PORT + POOL_SIZE - 1)) ct state new limit rate over ${RATE}/second drop
    }
}
NFT
}
rate_off() { sudo nft delete table inet anonymous_socks 2>/dev/null || true; }

# proxychains' LD_PRELOAD misses static binaries, raw sockets and udp, so anything in the slice may only talk to lo
egress_on() {
    local slice="user.slice/user-$UID.slice/user@$UID.service/anonsocks.slice"
    systemctl --user start anonsocks.slice || return 1
    sudo nft -f - <<NFT
table inet anonymous_socks {
    chain egress {
        type filter hook output priority 0; policy accept;
        socket cgroupv2 level 4 "$slice" oif != "lo" reject
        # redirected to lo, e.g. portmaster's dns, the lookup still leaves in the clear
        socket cgroupv2 level 4 "$slice" ct status dnat reject
    }
}
NFT
}

persona_ttl() {
    case "$PERSONA_OS" in
        windows) echo 128 ;;
        macos | ios | linux | android) echo 64 ;;
        *) return 1 ;;
    esac
}

PERSONA_CHAIN=ANONSOCKS_PERSONA

# the jump from POSTROUTING into the persona chain, for one iptables binary; $1 iptables|ip6tables, $2 -A|-D
persona_jump() { sudo "$1" -t mangle "$2" POSTROUTING -m cgroup --path "$PERSONA_CGROUP" -j "$PERSONA_CHAIN"; }

# ttl/hop limit set only on packets whose socket lives in tor's cgroup; the xt targets idspoof used, own chain
persona_on() {
    [ "$PERSONA" = 1 ] || return 0
    local ttl ipt
    ttl=$(persona_ttl) || {
        err "unknown persona '$PERSONA_OS', persona off"
        return 0
    }
    PERSONA_CGROUP=$(systemctl --user show --property=ControlGroup --value "$TOR_UNIT")
    PERSONA_CGROUP="${PERSONA_CGROUP#/}"
    [ -n "$PERSONA_CGROUP" ] || {
        err "no cgroup for $TOR_UNIT, persona off"
        return 0
    }
    persona_off
    for ipt in iptables ip6tables; do
        sudo "$ipt" -t mangle -N "$PERSONA_CHAIN" 2>/dev/null || sudo "$ipt" -t mangle -F "$PERSONA_CHAIN"
        if [ "$ipt" = iptables ]; then
            sudo iptables -t mangle -A "$PERSONA_CHAIN" -j TTL --ttl-set "$ttl"
        else
            sudo ip6tables -t mangle -A "$PERSONA_CHAIN" -j HL --hl-set "$ttl"
        fi
        persona_jump "$ipt" -A || err "$ipt persona jump failed, tor runs without it"
    done
}

# the cgroup is gone once tor stops, so the jump is found by chain name rather than by its match
persona_off() {
    local ipt rule
    for ipt in iptables ip6tables; do
        sudo "$ipt" -t mangle -S POSTROUTING 2>/dev/null | { grep -F -- "-j $PERSONA_CHAIN" || true; } | while read -r rule; do
            # shellcheck disable=SC2086
            sudo "$ipt" -t mangle ${rule/-A/-D}
        done
        sudo "$ipt" -t mangle -F "$PERSONA_CHAIN" 2>/dev/null || true
        sudo "$ipt" -t mangle -X "$PERSONA_CHAIN" 2>/dev/null || true
    done
}

# verify one pool port reachable AND leaving via a Tor exit; nonzero on any doubt so a gating caller fails closed
check_port() {
    local port="$1" body ip
    body=$(curl -fsS --max-time 15 --socks5-hostname "127.0.0.1:$port" "$TOR_CHECK_URL") \
        || {
            err "no route to $TOR_CHECK_URL through :$port"
            return 1
        }
    case "$body" in
        *'"IsTor":true'*) ;;
        *)
            err ":$port exit is not a Tor node: fail closed ($body)"
            return 1
            ;;
    esac
    ip=$(echo "$body" | grep -o '"IP":"[^"]*"' | cut -d'"' -f4)
    echo "anonymous-socks ok: :$port tor exit ${ip:-unknown}"
}

# every port up and on a Tor exit; ports checked in parallel
check() {
    is_up || {
        err "tunnel down on 127.0.0.1:$PORT"
        return 1
    }
    local p pids=() ok=0
    for p in $(pool_ports); do
        check_port "$p" &
        pids+=("$!")
    done
    for p in "${pids[@]}"; do wait "$p" || ok=1; done
    return "$ok"
}

# fresh circuits for new streams via SIGNAL NEWNYM, cookie auth
newnym() {
    is_up || { err "tunnel down"; return 1; }
    [ -r "$COOKIE" ] || { err "control cookie unreadable at $COOKIE"; return 1; }
    local hex auth signal
    hex=$(od -An -v -tx1 "$COOKIE" | tr -d ' \n')
    exec 3<>"/dev/tcp/127.0.0.1/$CTRL_PORT" || { err "no control port on :$CTRL_PORT"; return 1; }
    printf 'AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n' "$hex" >&3
    IFS= read -r -t 5 auth <&3 || auth=""
    IFS= read -r -t 5 signal <&3 || signal=""
    exec 3<&- 3>&-
    # one reply per command: AUTHENTICATE, then SIGNAL
    if [[ "$auth" == 250* && "$signal" == 250* ]]; then
        echo "newnym: fresh circuits requested"
    else
        err "newnym: control refused (${signal:-$auth})"
        return 1
    fi
}

# [ProxyList] block spanning the pool; pair with round_robin and chain_len 1 so each connection exits on the next port
proxylist() {
    local p
    echo "[ProxyList]"
    for p in $(pool_ports); do echo "socks5 127.0.0.1 $p"; done
}

# full proxychains config for the live pool; regenerated on up so it always matches POOL_SIZE
proxyconf() {
    cat <<PC
# generated by anonymous-socks.sh on up, regenerated each time, do not edit by hand; round_robin + chain_len 1: one proxy per connection, so requests spread across the pool
round_robin
chain_len = 1
proxy_dns
tcp_read_time_out $PC_READ_TIMEOUT_MS
tcp_connect_time_out $PC_CONNECT_TIMEOUT_MS
PC
    proxylist
}

up() {
    require_tor
    if is_up; then
        err "already up"
        return 0
    fi
    rm -f "$VERIFIED"
    egress_on || {
        err "egress guard failed, not starting"
        down
        exit 1
    }
    mkdir -p "$DATADIR"
    chmod 700 "$DATADIR"
    # one SocksPort per slot, each its own SessionGroup plus Isolate* flags: independent per-destination circuits
    local socks_args=() i=0 p
    for p in $(pool_ports); do
        socks_args+=(--SocksPort "127.0.0.1:$p IsolateSOCKSAuth IsolateDestAddr IsolateDestPort SessionGroup=$i")
        i=$((i + 1))
    done
    # never read /etc/tor/torrc: its User directive would force a root start and break this unprivileged instance
    systemd-run --user --quiet --collect --unit="$TOR_UNIT" \
        "$(command -v "$TOR_BIN")" \
        -f "$DATADIR/torrc" --ignore-missing-torrc \
        --defaults-torrc "$DATADIR/torrc-defaults" --ignore-missing-torrc \
        --RunAsDaemon 0 \
        "${socks_args[@]}" \
        --ControlPort "127.0.0.1:$CTRL_PORT" \
        --CookieAuthentication 1 \
        --MaxCircuitDirtiness "$MAX_DIRTINESS_S" \
        --DataDirectory "$DATADIR" \
        --Log "notice stderr"
    rate_on
    persona_on
    # wall-clock deadline: one check pass can take up to curl's 15s
    local deadline=$((SECONDS + BOOTSTRAP_TIMEOUT_S))
    until check; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            err "verification failed after ${BOOTSTRAP_TIMEOUT_S}s, tearing down"
            down
            exit 1
        fi
        sleep "$BOOTSTRAP_POLL_S"
    done
    touch "$VERIFIED"
    proxyconf >"$PC_CONF"
    echo "anonymous-socks up: $POOL_SIZE ports, round-robin config at $PC_CONF"
}

down() {
    # kills what still runs in the slice before the guard goes, so nothing continues unguarded
    systemctl --user stop anonsocks.slice 2>/dev/null || true
    rate_off
    persona_off
    rm -f "$PC_CONF" "$VERIFIED"
    systemctl --user stop "$TOR_UNIT" 2>/dev/null || true
}

# no Tor round trip: that took 24s and blocked the toggle menu
status() { if [ -e "$VERIFIED" ] && is_up; then echo on; else echo off; fi; }

case "${1:-status}" in
    up) up ;;
    down) down ;;
    check) check ;;
    status) status ;;
    newnym) newnym ;;
    proxylist) proxylist ;;
    proxyconf) proxyconf ;;
    *)
        echo "usage: anonymous-socks.sh {up|down|check|status|newnym|proxylist|proxyconf}" >&2
        exit 1
        ;;
esac
