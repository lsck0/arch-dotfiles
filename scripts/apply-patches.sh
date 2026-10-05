#!/usr/bin/env bash
# run patches/NN_<slug>.sh fixups once per machine in numeric order (recorded in $STATE_FILE outside git, so stay idempotent) to undo what an older config did that config.sh relinking cannot: dangling links, stale pam lines, enabled units
# usage: apply-patches [--list] [--force <name>...] [--dry-run]

set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

PATCH_DIR="$PWD/patches"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
STATE_FILE="$STATE_DIR/patches-applied"

mode=run
dry_run=0
forced=()

while (($#)); do
    case "$1" in
        --list) mode=list ;;
        --dry-run) dry_run=1 ;;
        --force)
            shift
            [[ $# -gt 0 ]] || { echo "apply-patches: --force needs a patch name" >&2; exit 1; }
            forced+=("$1")
            ;;
        -h | --help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "apply-patches: unknown argument '$1'" >&2
            exit 1
            ;;
    esac
    shift
done

[[ -d "$PATCH_DIR" ]] || exit 0

mkdir -p "$STATE_DIR"
touch "$STATE_FILE"

applied() { grep -qxF "$1" "$STATE_FILE"; }

shopt -s nullglob
patches=("$PATCH_DIR"/[0-9][0-9]_*.sh)
((${#patches[@]})) || exit 0

if [[ "$mode" == list ]]; then
    for patch in "${patches[@]}"; do
        name=$(basename "$patch")
        if applied "$name"; then printf 'applied  %s\n' "$name"; else printf 'pending  %s\n' "$name"; fi
    done
    exit 0
fi

status=0
for patch in "${patches[@]}"; do
    name=$(basename "$patch")
    wanted=0
    if ((${#forced[@]})); then
        for f in "${forced[@]}"; do [[ "$f" == "$name" || "$f" == "${name%.sh}" ]] && wanted=1; done
    elif ! applied "$name"; then
        wanted=1
    fi
    ((wanted)) || continue

    if ((dry_run)); then
        echo "patch: would run $name"
        continue
    fi

    echo "patch: $name"
    if bash "$patch" </dev/null; then
        applied "$name" || echo "$name" >>"$STATE_FILE"
    else
        echo "patch: $name failed, leaving it pending" >&2
        status=1
    fi
done

exit "$status"
