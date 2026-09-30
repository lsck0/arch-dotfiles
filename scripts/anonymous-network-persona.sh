#!/usr/bin/env bash
set -euo pipefail

# Global idspoof persona for every network; mutually exclusive with anonymous-socks.sh's scoped one.

CONF="${ANONYMOUS_NETWORK_PERSONA_CONF:-$HOME/.config/anonymous-network-persona/config}"
# shellcheck disable=SC1090
[ -r "$CONF" ] && source "$CONF"

OS="${ANONYMOUS_NETWORK_PERSONA_OS:-windows}"      # windows, macos, ios, linux, android
SPOOF_MAC="${ANONYMOUS_NETWORK_PERSONA_MAC:-0}"    # 1 = also randomise MAC (L2); drops the link briefly
# who applied the idspoof persona: socks or persona; shared with anonymous-socks.sh
IDSPOOF_OWNER="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/idspoof-owner"

err() { echo "anonymous-network-persona: $*" >&2; }

require_idspoof() {
    command -v idspoof >/dev/null || {
        err "idspoof not found (mirror/pkgbuilds/idspoof)"
        exit 1
    }
}

# idspoof operation flags: network persona always, MAC only when asked.
persona_ops() { if [ "$SPOOF_MAC" = 1 ]; then echo "--mac --netident"; else echo "--netident"; fi; }

owner() { cat "$IDSPOOF_OWNER" 2>/dev/null || true; }

up() {
    require_idspoof
    if [ "$(owner)" = socks ]; then
        err "anonymous-socks pool has its own persona and a global one breaks its circuits; down the pool first"
        exit 1
    fi
    # shellcheck disable=SC2046
    sudo idspoof apply $(persona_ops) --persona "$OS" -q
    echo persona >"$IDSPOOF_OWNER"
}

down() {
    require_idspoof
    if [ "$(owner)" = socks ]; then
        err "persona belongs to the anonymous-socks pool; down the pool instead"
        exit 1
    fi
    # shellcheck disable=SC2046
    sudo idspoof restore $(persona_ops) -q 2>/dev/null || true
    rm -f "$IDSPOOF_OWNER"
}

# the pool's persona is not this toggle; without an owner file (reboot) fall back to TTL/timestamps
status() {
    case "$(owner)" in
    persona) echo on; return ;;
    socks) echo off; return ;;
    esac
    local ttl ts
    ttl=$(sysctl -n net.ipv4.ip_default_ttl 2>/dev/null || echo 64)
    ts=$(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null || echo 1)
    if [ "$ttl" != 64 ] || [ "$ts" != 1 ]; then echo on; else echo off; fi
}

case "${1:-status}" in
    up) up ;;
    down) down ;;
    status) status ;;
    *)
        echo "usage: anonymous-network-persona.sh {up|down|status}" >&2
        exit 1
        ;;
esac
