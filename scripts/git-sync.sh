#!/usr/bin/env bash
# Sync all git repos recursively, skipping submodules. Prunes vendor/, heavy
# build/cache dirs and gitignored repos; fetches/pulls in parallel.

BASE_DIR=$(realpath "${1:-.}")
JOBS="${GIT_SYNC_JOBS:-8}"

# One `sh -c` per candidate dir (was three `test` execs); prune vendor + heavy trees so find never descends them.
mapfile -t dirs < <(
    find "$BASE_DIR" -maxdepth 4 \
        -type d \( -name vendor -o -name node_modules -o -name .cache -o -name target -o -name .venv -o -name .direnv \) -prune -o \
        -type d \
        \( -name '.git' -o \
           -exec sh -c 'test -e "$1/HEAD" && test -d "$1/objects" && test -d "$1/refs"' _ {} \; \) \
        -prune -print 2>/dev/null |
        sed 's|/\.git$||' | sort -u
)

# Drop repos that their containing repo git-ignores (e.g. build/cache dirs).
kept=()
for dir in "${dirs[@]}"; do
    top=$(git -C "$(dirname "$dir")" rev-parse --show-toplevel 2>/dev/null)
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

# Per-repo work; run in parallel. Builds the whole status line, then prints it once (atomic enough for a status log).
sync_one() {
    local dir="$1"
    local rel="${dir#"$BASE_DIR"/}"
    local statuses=()

    local bare
    bare=$(git -C "$dir" rev-parse --is-bare-repository 2>/dev/null)

    if [[ "$bare" == "true" ]]; then
        local refs_before refs_after
        refs_before=$(git -C "$dir" for-each-ref --format='%(refname) %(objectname)' 2>/dev/null)
        git -C "$dir" fetch --all --prune --quiet 2>/dev/null || statuses+=("FETCH FAILED")
        refs_after=$(git -C "$dir" for-each-ref --format='%(refname) %(objectname)' 2>/dev/null)

        [[ "$refs_before" != "$refs_after" ]] && statuses+=("FETCHED")
        [[ -z $(git -C "$dir" remote 2>/dev/null) ]] && statuses+=("NO REMOTE")

        [[ ${#statuses[@]} -eq 0 ]] && statuses+=("UP TO DATE")
        printf "%-*s  %s  (bare)\n" "$pad" "$rel" "$(IFS=", "; echo "${statuses[*]}")"
        return
    fi

    local porcelain
    porcelain=$(git -C "$dir" status --porcelain 2>/dev/null)
    grep -q "^[MADRC]" <<< "$porcelain" && statuses+=("STAGED CHANGES")
    grep -q "^.[MADRC]" <<< "$porcelain" && statuses+=("UNSTAGED CHANGES")
    grep -q "^??" <<< "$porcelain" && statuses+=("UNTRACKED FILES")

    local upstream
    upstream=$(git -C "$dir" rev-parse --symbolic-full-name '@{u}' 2>/dev/null)
    if [[ -n "$upstream" ]]; then
        git -C "$dir" log '@{u}..HEAD' --oneline 2>/dev/null | grep -q . && statuses+=("UNPUSHED COMMITS")
    fi

    local refs_before refs_after
    refs_before=$(git -C "$dir" for-each-ref refs/remotes --format='%(refname) %(objectname)' 2>/dev/null)
    git -C "$dir" fetch --all --quiet 2>/dev/null || statuses+=("FETCH FAILED")
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

    if [[ -n "$upstream" ]] \
        && ! grep -q "STAGED CHANGES"   <<< "${statuses[*]}" \
        && ! grep -q "UNSTAGED CHANGES" <<< "${statuses[*]}" \
        && ! grep -q "UNPUSHED COMMITS" <<< "${statuses[*]}"; then
        local pull_output pull_exit
        pull_output=$(git -C "$dir" pull 2>&1)
        pull_exit=$?
        if [[ $pull_exit -ne 0 ]]; then
            statuses+=("PULL FAILED")
        elif ! grep -q "Already up to date" <<< "$pull_output"; then
            statuses+=("PULLED")
        fi
    fi

    [[ ${#statuses[@]} -eq 0 ]] && statuses+=("UP TO DATE")
    printf "%-*s  %s\n" "$pad" "$rel" "$(IFS=", "; echo "${statuses[*]}")"
}
export -f sync_one
export BASE_DIR pad

printf '%s\n' "${dirs[@]}" | xargs -r -P "$JOBS" -I{} bash -c 'sync_one "$@"' _ {}
