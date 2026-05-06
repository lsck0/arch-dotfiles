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

    if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
        printf "%-*s  %s\n" "$pad" "$rel" "LOCAL CHANGES"
        continue
    fi

    pull_output=$(git -C "$dir" pull 2>&1)
    if [[ $? -ne 0 ]]; then
        printf "%-*s  %s\n" "$pad" "$rel" "PULL FAILED"
    elif echo "$pull_output" | grep -q "Already up to date"; then
        printf "%-*s  %s\n" "$pad" "$rel" "UP TO DATE"
    else
        printf "%-*s  %s\n" "$pad" "$rel" "PULLED"
    fi
done
