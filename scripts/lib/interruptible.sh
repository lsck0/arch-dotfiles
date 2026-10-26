#!/usr/bin/env bash
# Runs a dot command so ctrl+c ends the whole run: nushell's try would catch the interrupt and go on, so on SIGINT
# every nu below and every setsid'd command get SIGTERM; exits 130. --lock <file> holds that flock for the run.
# DOT_RUN_POINTER names the file the run writes its log path into, so the interrupt is logged there too.
set -euo pipefail

if [[ ${1-} == --lock ]]; then
    exec 9>> "$2"
    flock 9
    shift 2
fi

interrupted=0
# shellcheck disable=SC2329 # the INT trap calls it
stop() {
    interrupted=1
    local victims
    victims=$(ps -e -o pid=,ppid=,sid=,comm= | awk -v root=$$ -v sid="$sid" '
		{ parent[$1] = $2; session[$1] = $3; name[$1] = $4 }
		END {
			for (p in parent) {
				q = parent[p]
				while (q != root && q in parent) q = parent[q]
				if (q == root && (name[p] == "nu" || session[p] != sid)) print p
			}
		}')
    if [[ -n $victims ]]; then
        # shellcheck disable=SC2086 # one pid per word
        kill -TERM $victims 2> /dev/null || true
    fi
}

sid=$(ps -o sid= -p $$ | tr -d ' ')
pointer=$(mktemp --tmpdir dot-run.XXXXXX)
trap 'rm -f "$pointer"' EXIT
trap stop INT
# an asynchronous command starts with SIGINT ignored and stdin on /dev/null: undo both
exec 3<&0
(
    trap - INT
    exec env DOT_INTERRUPTIBLE="$sid" DOT_RUN_POINTER="$pointer" "$@" <&3 3<&- 9<&-
) &
child=$!
exec 3<&-

status=0
while :; do
    wait "$child" && status=0 || status=$?
    kill -0 "$child" 2> /dev/null || break
done

if ((interrupted)); then
    message="interrupted (ctrl+c): the run stopped, its later phases did not run"
    echo "dot: $message" >&2
    logger -t dot -- "$message" 2> /dev/null || true
    run=$(cat "$pointer")
    if [[ -n $run && -f $run ]]; then
        id=$(basename "$run" .jsonl)
        printf '{"time":"%s","level":"ERROR","run":"%s","span":"","module":"","verb":"","msg":"%s","kind":"interrupted"}\n' \
            "$(date --iso-8601=seconds)" "$id" "$message" >> "$run"
    fi
    exit 130
fi
exit "$status"
