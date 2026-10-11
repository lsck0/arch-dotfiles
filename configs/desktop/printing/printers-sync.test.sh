#!/usr/bin/env bash
# printers-sync.sh against canned lpinfo output and a stubbed cups, no root: one queue per printer, on its .local
# service name, the default only where none was set, and a rerun changes nothing. run by ./test.py lint
set -euo pipefail

SYNC="$(cd "$(dirname "$0")" && pwd)/printers-sync.sh"
WANT_NAME=HP_ENVY_5640_series_B8A730
WANT_URI='dnssd://HP%20ENVY%205640%20series%20%5BB8A730%5D._ipp._tcp.local/?uuid=1c852a4d-b800-1f08-abcd-b8a730000001'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
export STUB_STATE="$work"
: >"$work/queues"
: >"$work/calls"

# the same printer over ipp and ipps, an lpd-only printer, and an address that must never become a queue
cat >"$work/lpinfo.out" <<EOF
network $WANT_URI
network dnssd://HP%20ENVY%205640%20series%20%5BB8A730%5D._ipps._tcp.local/?uuid=1c852a4d-b800-1f08-abcd-b8a730000001
network dnssd://Old%20Laser._printer._tcp.local/?uuid=00000000-0000-0000-0000-000000000002
network dnssd://Old%20Laser._pdl-datastream._tcp.local/?uuid=00000000-0000-0000-0000-000000000002
network ipp://192.168.178.20/ipp/print
EOF

cat >"$work/bin/lpinfo" <<'EOF'
#!/usr/bin/env bash
cat "$STUB_STATE/lpinfo.out"
EOF
# queues: "<name> <uri>" lines; default: the default queue's name
cat >"$work/bin/lpstat" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -v) while read -r name uri; do echo "device for $name: $uri"; done <"$STUB_STATE/queues" ;;
    -p) grep -q "^$2 " "$STUB_STATE/queues" ;;
    -d) if [[ -s "$STUB_STATE/default" ]]; then echo "system default destination: $(<"$STUB_STATE/default")"
        else echo "no system default destination"; fi ;;
esac
EOF
cat >"$work/bin/lpadmin" <<'EOF'
#!/usr/bin/env bash
echo "lpadmin $*" >>"$STUB_STATE/calls"
name="" uri=""
while (($#)); do
    case "$1" in
        -p) name=$2; shift ;;
        -v) uri=$2; shift ;;
        -d) echo "$2" >"$STUB_STATE/default" ;;
    esac
    shift
done
[[ -z "$name" ]] || echo "$name $uri" >>"$STUB_STATE/queues"
EOF
chmod +x "$work/bin/"*

fail() { echo "printers-sync.test: $*" >&2; exit 1; }

PATH="$work/bin:$PATH" bash "$SYNC" 2>/dev/null || fail "first run failed"
[[ "$(<"$work/queues")" == "$WANT_NAME $WANT_URI" ]] || fail "want exactly one queue $WANT_NAME on $WANT_URI, got: $(<"$work/queues")"
[[ "$(<"$work/default")" == "$WANT_NAME" ]] || fail "the new queue did not become the default"
grep -q -- '-m everywhere' "$work/calls" || fail "the queue is not an IPP Everywhere one"

: >"$work/calls"
PATH="$work/bin:$PATH" bash "$SYNC" 2>/dev/null || fail "rerun failed"
[[ ! -s "$work/calls" ]] || fail "rerun was not a no-op: $(<"$work/calls")"

# a default someone chose stays
: >"$work/queues"
echo PDF >"$work/default"
PATH="$work/bin:$PATH" bash "$SYNC" 2>/dev/null || fail "run with a default failed"
[[ "$(<"$work/default")" == PDF ]] || fail "a set default was replaced"

echo "printers-sync.test: ok"
