#!/usr/bin/env bash

set -e

LAST_GEN=$(git log --format=%s | grep -m1 -oE '^Generation: [0-9]+' | grep -oE '[0-9]+' || echo 0)
COMMIT_MSG="Generation: $((LAST_GEN + 1))"

git add .
git commit -S -m "${COMMIT_MSG}"
git push
