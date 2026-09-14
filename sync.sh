#!/usr/bin/env bash

set -e

# Commit message is always exactly "Generation: N" -- no extra words, no
# body. N = one more than the last commit that actually matched this
# pattern; searched back through history (not just HEAD) so an off-pattern
# commit slipped in by hand or another tool doesn't stall the counter or
# get its wording carried forward into the next commit.
LAST_GEN=$(git log --format=%s | grep -m1 -oE '^Generation: [0-9]+' | grep -oE '[0-9]+' || echo 0)
COMMIT_MSG="Generation: $((LAST_GEN + 1))"

git add .
git commit -S -m "${COMMIT_MSG}"
git push
