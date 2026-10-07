#!/usr/bin/env bash
# Fetch, pull and push every git repo under a dir in parallel, skipping submodules, vendor/, heavy build/cache and gitignored repos.

set -euo pipefail

BASE_DIR=$(realpath "${1:-.}")
JOBS="${GIT_SYNC_JOBS:-8}"

# prune vendor + heavy trees so find never descends them
mapfile -t dirs < <(
    find "$BASE_DIR" -maxdepth 5 \
        -type d \( -name vendor -o -name node_modules -o -name .cache -o -name target -o -name .venv -o -name .direnv -o -path '*/.git/*' \) -prune -o \
        -type f -name HEAD -printf '%h\n' 2>/dev/null |
        while read -r d; do [[ -d $d/objects && -d $d/refs ]] && printf '%s\n' "$d"; done |
        sed 's|/\.git$||' | sort -u
)

# Drop repos that their containing repo git-ignores (e.g. build/cache dirs).
kept=()
for dir in "${dirs[@]}"; do
    top=$(git -C "$(dirname "$dir")" rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$top" && "$top" != "$dir" ]] && git -C "$top" check-ignore -q "$dir" 2>/dev/null; then
        continue
    fi
    kept+=("$dir")
done
dirs=("${kept[@]}")

pad=0
for dir in "${dirs[@]}"; do
    rel="${dir#"$BASE_DIR"/}"
    (( ${#rel} > pad )) && pad=${#rel}
done

# per-repo work, run in parallel; build the status line then print it once
sync_one() {
    local dir="$1"
    local rel="${dir#"$BASE_DIR"/}"
    local statuses=()
    local g=(git)
    # customer repos fetch and push with their own credentials
    [[ -e $dir/.identity/envrc ]] && g=(direnv exec "$dir" git)

    local bare
    bare=$(git -C "$dir" rev-parse --is-bare-repository 2>/dev/null)

    if [[ "$bare" == "true" ]]; then
        local refs_before refs_after
        refs_before=$(git -C "$dir" for-each-ref --format='%(refname) %(objectname)' 2>/dev/null)
        "${g[@]}" -C "$dir" fetch --all --prune --quiet 2>/dev/null || statuses+=("FETCH FAILED")
        refs_after=$(git -C "$dir" for-each-ref --format='%(refname) %(objectname)' 2>/dev/null)

        [[ "$refs_before" != "$refs_after" ]] && statuses+=("FETCHED")
        [[ -z $(git -C "$dir" remote 2>/dev/null) ]] && statuses+=("NO REMOTE")

        [[ ${#statuses[@]} -eq 0 ]] && statuses+=("UP TO DATE")
        printf "%-*s  %s  (bare)\n" "$pad" "$rel" "$(IFS=", "; echo "${statuses[*]}")"
        return
    fi

    local porcelain dirty=0 unpushed=0
    porcelain=$(git -C "$dir" status --porcelain 2>/dev/null)
    grep -q "^[MADRC]" <<< "$porcelain" && statuses+=("STAGED CHANGES") && dirty=1
    grep -q "^.[MADRC]" <<< "$porcelain" && statuses+=("UNSTAGED CHANGES") && dirty=1
    grep -q "^??" <<< "$porcelain" && statuses+=("UNTRACKED FILES")

    local upstream
    upstream=$(git -C "$dir" rev-parse --symbolic-full-name '@{u}' 2>/dev/null)
    if [[ -n "$upstream" ]]; then
        git -C "$dir" log '@{u}..HEAD' --oneline 2>/dev/null | grep -q . && statuses+=("UNPUSHED COMMITS") && unpushed=1
    fi

    local refs_before refs_after
    refs_before=$(git -C "$dir" for-each-ref refs/remotes --format='%(refname) %(objectname)' 2>/dev/null)
    "${g[@]}" -C "$dir" fetch --all --quiet 2>/dev/null || statuses+=("FETCH FAILED")
    refs_after=$(git -C "$dir" for-each-ref refs/remotes --format='%(refname) %(objectname)' 2>/dev/null)

    if [[ "$refs_before" != "$refs_after" ]]; then
        if [[ -n "$upstream" ]]; then
            local before_others after_others
            before_others=$(awk -v u="$upstream " 'index($0, u) != 1' <<< "$refs_before")
            after_others=$(awk  -v u="$upstream " 'index($0, u) != 1' <<< "$refs_after")
            [[ "$before_others" != "$after_others" ]] && statuses+=("FETCHED")
        else
            statuses+=("FETCHED")
        fi
    fi

    if [[ -n "$upstream" ]] && (( !dirty && !unpushed )); then
        local pull_output pull_exit
        pull_output=$("${g[@]}" -C "$dir" pull 2>&1)
        pull_exit=$?
        if [[ $pull_exit -ne 0 ]]; then
            statuses+=("PULL FAILED")
        elif ! grep -q "Already up to date" <<< "$pull_output"; then
            statuses+=("PULLED")
        fi
    fi

    # push commits the remote is missing; non-force, so a diverged branch just reports PUSH FAILED
    if [[ -n "$upstream" ]] && git -C "$dir" log '@{u}..HEAD' --oneline 2>/dev/null | grep -q .; then
        if "${g[@]}" -C "$dir" push --quiet 2>/dev/null; then
            statuses=("${statuses[@]/UNPUSHED COMMITS/PUSHED}")
        else
            statuses+=("PUSH FAILED")
        fi
    fi

    [[ ${#statuses[@]} -eq 0 ]] && statuses+=("UP TO DATE")
    printf "%-*s  %s\n" "$pad" "$rel" "$(IFS=", "; echo "${statuses[*]}")"
}
export -f sync_one
export BASE_DIR pad

printf '%s\n' "${dirs[@]}" | xargs -r -P "$JOBS" -I{} bash -c 'sync_one "$@"' _ {}
