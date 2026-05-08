#!/usr/bin/env bash
# Sync all git repos recursively, skipping submodules.

BASE_DIR=$(realpath "${1:-.}")

mapfile -t dirs < <(find "$BASE_DIR" -name ".git" -type d -prune 2>/dev/null | sed 's|/.git$||' | sort)

pad=0
for dir in "${dirs[@]}"; do
    rel="${dir#$BASE_DIR/}"
    (( ${#rel} > pad )) && pad=${#rel}
done

for dir in "${dirs[@]}"; do
    rel="${dir#$BASE_DIR/}"
    statuses=()

    porcelain=$(git -C "$dir" status --porcelain 2>/dev/null)
    grep -q "^[MADRC]" <<< "$porcelain" && statuses+=("STAGED CHANGES")
    grep -q "^.[MD]"   <<< "$porcelain" && statuses+=("UNSTAGED CHANGES")

    upstream=$(git -C "$dir" rev-parse --symbolic-full-name '@{u}' 2>/dev/null)

    if [[ -n "$upstream" ]]; then
        git -C "$dir" log '@{u}..HEAD' --oneline 2>/dev/null | grep -q . && statuses+=("UNPUSHED COMMITS")
    fi

    refs_before=$(git -C "$dir" for-each-ref refs/remotes --format='%(refname) %(objectname)' 2>/dev/null)
    git -C "$dir" fetch --all --quiet 2>/dev/null
    refs_after=$(git -C "$dir" for-each-ref refs/remotes --format='%(refname) %(objectname)' 2>/dev/null)

    if [[ "$refs_before" != "$refs_after" ]]; then
        if [[ -n "$upstream" ]]; then
            before_others=$(awk -v u="$upstream " 'index($0, u) != 1' <<< "$refs_before")
            after_others=$(awk  -v u="$upstream " 'index($0, u) != 1' <<< "$refs_after")
            [[ "$before_others" != "$after_others" ]] && statuses+=("FETCHED")
        else
            statuses+=("FETCHED")
        fi
    fi

    safe_to_pull=false
    if [[ -n "$upstream" ]] \
        && ! grep -q "STAGED CHANGES"   <<< "${statuses[*]}" \
        && ! grep -q "UNSTAGED CHANGES" <<< "${statuses[*]}" \
        && ! grep -q "UNPUSHED COMMITS" <<< "${statuses[*]}"; then
        safe_to_pull=true
    fi

    if $safe_to_pull; then
        pull_output=$(git -C "$dir" pull 2>&1)
        pull_exit=$?
        if [[ $pull_exit -ne 0 ]]; then
            statuses+=("PULL FAILED")
        elif ! grep -q "Already up to date" <<< "$pull_output"; then
            statuses+=("PULLED")
        fi
    fi

    [[ ${#statuses[@]} -eq 0 ]] && statuses+=("UP TO DATE")

    status_str=$(IFS=", "; echo "${statuses[*]}")
    printf "%-*s  %s\n" "$pad" "$rel" "$status_str"
done
