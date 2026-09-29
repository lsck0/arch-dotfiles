#!/usr/bin/env bash
# Single declared SOCKS egress for authorized testing. One ssh -D tunnel to the
# agreed jump host, verified so every tool routed through it leaves from the one
# source IP the client authorized, and fails closed when it cannot prove that.
# This is not an anonymizer: one known, logged source, so the blue team can
# deconflict the traffic. Route a tool through it with:
#   proxychains4 -f ~/.proxychains/proxychains.conf nmap -sT -Pn <target>
# or point ZAP's outbound SOCKS proxy at 127.0.0.1:<port>.
set -euo pipefail

# Host and the authorized source IP live outside the repo (per-engagement, and
# host is sensitive). Provide them in $EGRESS_CONF or the environment.
CONF="${EGRESS_CONF:-$HOME/.config/egress/config}"
# shellcheck disable=SC1090
[ -r "$CONF" ] && source "$CONF"

HOST="${EGRESS_HOST:-}"               # ssh destination, e.g. user@jump.example.com
EXIT_IP="${EGRESS_EXIT_IP:-}"         # the source IP the engagement authorized
PORT="${EGRESS_SOCKS_PORT:-9050}"
RATE="${EGRESS_RATE:-0}"              # max new SOCKS connections/sec, 0 = uncapped
IP_ECHO="${EGRESS_IP_ECHO:-https://api.ipify.org}"
PIDFILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/egress.pid"

err() { echo "egress: $*" >&2; }

is_up() { ss -tlnH "sport = :$PORT" 2>/dev/null | grep -q .; }

# Coarse rules-of-engagement throttle: cap how fast tools may open new SOCKS
# sessions. Own nft table so it never touches the firewall's inet fw table.
rate_on() {
    [ "$RATE" -gt 0 ] 2>/dev/null || return 0
    command -v nft >/dev/null || { err "nft missing, running without rate cap"; return 0; }
    sudo nft -f - <<NFT
table inet egress {
    chain out {
        type filter hook output priority 0; policy accept;
        oif "lo" tcp dport $PORT ct state new limit rate over ${RATE}/second drop
    }
}
NFT
}
rate_off() { sudo nft delete table inet egress 2>/dev/null || true; }

# Verify the proxy is up AND exits from the declared IP. Nonzero on any doubt,
# so a caller that gates on this never falls back to the real source.
check() {
    is_up || { err "tunnel down on 127.0.0.1:$PORT"; return 1; }
    [ -n "$EXIT_IP" ] || { err "EGRESS_EXIT_IP unset: cannot verify source, refusing"; return 1; }
    local seen
    seen=$(curl -fsS --max-time 15 --socks5-hostname "127.0.0.1:$PORT" "$IP_ECHO") \
        || { err "no route to $IP_ECHO through the proxy"; return 1; }
    if [ "$seen" != "$EXIT_IP" ]; then
        err "exit IP $seen != declared $EXIT_IP: fail closed"
        return 1
    fi
    echo "egress ok: exit $seen"
}

up() {
    [ -n "$HOST" ]    || { err "EGRESS_HOST unset (see $CONF)"; exit 1; }
    [ -n "$EXIT_IP" ] || { err "EGRESS_EXIT_IP unset: refusing, cannot verify source"; exit 1; }
    if is_up; then
        err "already up"
    else
        # ExitOnForwardFailure: fail loudly if the SOCKS port cannot bind, rather
        # than leaving a live ssh with no proxy that tools would then bypass.
        ssh -f -N -D "127.0.0.1:$PORT" -o ExitOnForwardFailure=yes "$HOST"
        pgrep -f "ssh -f -N -D 127.0.0.1:$PORT" >"$PIDFILE" || true
    fi
    rate_on
    check || { err "verification failed, tearing down"; down; exit 1; }
}

down() {
    rate_off
    if [ -r "$PIDFILE" ]; then kill "$(cat "$PIDFILE")" 2>/dev/null || true; rm -f "$PIDFILE"; fi
    pkill -f "ssh -f -N -D 127.0.0.1:$PORT" 2>/dev/null || true
}

# on only when the tunnel is up and still verifies against the declared IP.
status() { if is_up && check >/dev/null 2>&1; then echo on; else echo off; fi; }

case "${1:-status}" in
    up)     up ;;
    down)   down ;;
    check)  check ;;
    status) status ;;
    *)      echo "usage: egress.sh {up|down|check|status}" >&2; exit 1 ;;
esac
