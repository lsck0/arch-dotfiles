#!/usr/bin/env bash
# run patches/NN_<slug>.sh fixups that undo what an older config did and relinking cannot: dangling links, stale pam lines, enabled units
# two scopes by name: NN_slug.sh is the machine's (root, from system-apply, after the system modules), NN_slug.user.sh the
# running user's (config.sh, before the user modules); a patch runs once per record, a fresh machine or user is pre-marked
# usage: apply-patches [--list] [--force <name>...] [--dry-run] [--mark-applied]

set -uo pipefail
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# patches read it
export DOTFILES
cd "$DOTFILES" || exit 1
source ./scripts/lib/system.sh

PATCH_DIR="$PWD/patches"
if ((EUID == 0)); then
    STATE_FILE="$SYSTEM_STATE/patches-applied"
else
    STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/patches-applied"
fi

mode=run
dry_run=0
forced=()

while (($#)); do
    case "$1" in
        --list) mode=list ;;
        --dry-run) dry_run=1 ;;
        # bootstrap.sh and adduser-dotfiles: everything in the repo already describes this fresh machine or user
        --mark-applied) mode=mark ;;
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

shopt -s nullglob
user_scope=1
((EUID != 0)) || user_scope=0
patches=()
for patch in "$PATCH_DIR"/[0-9][0-9]_*.sh; do
    user_patch=0
    [[ "$patch" != *.user.sh ]] || user_patch=1
    ((user_patch != user_scope)) || patches+=("$patch")
done
((${#patches[@]})) || exit 0

mkdir -p "${STATE_FILE%/*}"
touch "$STATE_FILE"
applied() { grep -qxF "$1" "$STATE_FILE"; }

if [[ "$mode" == list ]]; then
    for patch in "${patches[@]}"; do
        name=$(basename "$patch")
        if applied "$name"; then printf 'applied %s\n' "$name"; else printf 'pending %s\n' "$name"; fi
    done
    exit 0
fi

status=0
for patch in "${patches[@]}"; do
    name=$(basename "$patch")
    wanted=0
    if [[ "$mode" == mark ]]; then
        applied "$name" || echo "$name" >>"$STATE_FILE"
        continue
    elif ((${#forced[@]})); then
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
