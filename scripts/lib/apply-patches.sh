#!/usr/bin/env bash
# run patches/NN_<slug>.sh fixups that undo what an older config did and config.sh relinking cannot: dangling links, stale pam lines, enabled units
# a patch runs once per machine (recorded in $STATE_FILE, idempotent) and only when it is younger than this machine's install, so a fresh install replays nothing
# usage: apply-patches [--list] [--force <name>...] [--dry-run]

set -uo pipefail
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
cd "$DOTFILES" || exit 1

PATCH_DIR="$PWD/patches"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
STATE_FILE="$STATE_DIR/patches-applied"
INSTALL_FILE="$STATE_DIR/install-date"

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
# the install moment, stamped on the first run; patches committed before it belong to an earlier machine and never apply here
[[ -f "$INSTALL_FILE" ]] || date +%s >"$INSTALL_FILE"
install_date=$(cat "$INSTALL_FILE")

applied() { grep -qxF "$1" "$STATE_FILE"; }
# a patch's age is its last commit; an uncommitted one falls back to its mtime
patch_date() {
    local d
    d=$(git -C "$DOTFILES" log -1 --format=%ct -- "$1" 2>/dev/null)
    [[ -n "$d" ]] && { echo "$d"; return; }
    stat -c %Y "$1"
}
younger() { (($(patch_date "$1") > install_date)); }

shopt -s nullglob
patches=("$PATCH_DIR"/[0-9][0-9]_*.sh)
((${#patches[@]})) || exit 0

if [[ "$mode" == list ]]; then
    for patch in "${patches[@]}"; do
        name=$(basename "$patch")
        if applied "$name"; then printf 'applied   %s\n' "$name"
        elif ! younger "$patch"; then printf 'preinstall %s\n' "$name"
        else printf 'pending   %s\n' "$name"; fi
    done
    exit 0
fi

status=0
for patch in "${patches[@]}"; do
    name=$(basename "$patch")
    wanted=0
    if ((${#forced[@]})); then
        for f in "${forced[@]}"; do [[ "$f" == "$name" || "$f" == "${name%.sh}" ]] && wanted=1; done
    elif ! applied "$name" && younger "$patch"; then
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
