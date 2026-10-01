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
PIDFILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/anonymous-socks.pid"
# exists only after up verified every port exits through Tor
VERIFIED="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/anonymous-socks.verified"
# who applied the idspoof persona: socks or persona; shared with anonymous-network-persona.sh
IDSPOOF_OWNER="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/idspoof-owner"

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

# adaptive idspoof persona scoped by destination: external gets TTL/MSS/sysctl only (its NFQUEUE reorder
# mangles Tor guard SYNs), internal nets get the full persona incl the reorder (LAN fingerprints at the wire)
PERSONA="${ANONYMOUS_SOCKS_PERSONA:-1}"              # adaptive persona with the tunnel; 0 = disable
PERSONA_OS="${ANONYMOUS_SOCKS_PERSONA_OS:-windows}"  # idspoof persona: windows, macos, ios, linux, android
PERSONA_NFQUEUE_NUM=42                               # idspoof's option-reorder queue (its IDSPOOF_NETEMU rule)
PERSONA_INTERNAL_NETS="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16"

# Tor Project's exit check; verifying against it proves traffic left via a Tor exit (exit IP rotates per circuit)
TOR_CHECK_URL="${ANONYMOUS_SOCKS_TOR_CHECK_URL:-https://check.torproject.org/api/ip}"

# Tor builds a circuit before the first request can exit; poll check() this long after start
BOOTSTRAP_TIMEOUT_S=60
BOOTSTRAP_POLL_S=2

err() { echo "anonymous-socks: $*" >&2; }

# Up only when every pool port is listening, so a half-started daemon reads down.
is_up() {
    local p
    for p in $(pool_ports); do
        ss -tlnH "sport = :$p" 2>/dev/null | grep -q . || return 1
    done
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

# persona with the NFQUEUE reorder scoped to internal nets, so Tor guard SYNs survive
persona_on() {
    [ "$PERSONA" = 1 ] || return 0
    command -v idspoof >/dev/null || {
        err "idspoof not found, persona off (mirror/pkgbuilds/idspoof)"
        return 0
    }
    sudo idspoof apply --netident --persona "$PERSONA_OS" -q || {
        err "idspoof apply failed, persona not active"
        return 0
    }
    echo socks >"$IDSPOOF_OWNER"
    persona_scope_nfqueue || {
        err "could not scope NFQUEUE to internal, dropping the reorder to keep the pool alive"
        persona_drop_nfqueue
    }
}

# replace idspoof's blanket mangle/IDSPOOF_NETEMU reorder with one copy per internal net; nonzero if its rule is gone
persona_scope_nfqueue() {
    local q=(-p tcp -m tcp --tcp-flags SYN,RST,ACK SYN -j NFQUEUE --queue-num "$PERSONA_NFQUEUE_NUM")
    sudo iptables -t mangle -C IDSPOOF_NETEMU "${q[@]}" 2>/dev/null || return 1
    sudo iptables -t mangle -D IDSPOOF_NETEMU "${q[@]}"
    local net
    for net in $PERSONA_INTERNAL_NETS; do
        sudo iptables -t mangle -A IDSPOOF_NETEMU -d "$net" "${q[@]}"
    done
}

# Fallback: strip the blanket reorder entirely so it cannot break the pool.
persona_drop_nfqueue() {
    sudo iptables -t mangle -D IDSPOOF_NETEMU \
        -p tcp -m tcp --tcp-flags SYN,RST,ACK SYN -j NFQUEUE --queue-num "$PERSONA_NFQUEUE_NUM" 2>/dev/null || true
}

# only undo a persona this script applied
persona_off() {
    [ "$(cat "$IDSPOOF_OWNER" 2>/dev/null)" = socks ] || return 0
    command -v idspoof >/dev/null && { sudo idspoof restore --netident -q 2>/dev/null || true; }
    rm -f "$IDSPOOF_OWNER"
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
# Generated by anonymous-socks.sh on up; regenerated each time. Do not edit by hand.
# round_robin + chain_len 1: one proxy per connection, so requests spread across the pool.
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
    local owner
    owner=$(cat "$IDSPOOF_OWNER" 2>/dev/null || true)
    if [ "$owner" = persona ]; then
        err "global network persona is on and breaks Tor circuits; turn it off first"
        exit 1
    fi
    rm -f "$VERIFIED"
    mkdir -p "$DATADIR"
    chmod 700 "$DATADIR"
    # one SocksPort per slot, each its own SessionGroup plus Isolate* flags: independent per-destination circuits
    local socks_args=() i=0 p
    for p in $(pool_ports); do
        socks_args+=(--SocksPort "127.0.0.1:$p IsolateSOCKSAuth IsolateDestAddr IsolateDestPort SessionGroup=$i")
        i=$((i + 1))
    done
    # never read /etc/tor/torrc: its User directive would force a root start and break this unprivileged instance
    "$TOR_BIN" \
        -f "$DATADIR/torrc" --ignore-missing-torrc \
        --defaults-torrc "$DATADIR/torrc-defaults" --ignore-missing-torrc \
        --RunAsDaemon 1 \
        "${socks_args[@]}" \
        --ControlPort "127.0.0.1:$CTRL_PORT" \
        --CookieAuthentication 1 \
        --MaxCircuitDirtiness "$MAX_DIRTINESS_S" \
        --DataDirectory "$DATADIR" \
        --PidFile "$PIDFILE" \
        --Log "notice stderr" >/dev/null
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
    rate_off
    persona_off
    rm -f "$PC_CONF" "$VERIFIED"
    if [ -r "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
        rm -f "$PIDFILE"
    fi
    pkill -f "$TOR_BIN .* --SocksPort 127.0.0.1:$PORT" 2>/dev/null || true
}

# no Tor round trip: that took 24s and blocked the toggle menu
status() { if is_up && [ -e "$VERIFIED" ]; then echo on; else echo off; fi; }

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
