#!/bin/bash

set -e

git pull
git submodule update --init --recursive

# "Generation: n" from last commit -> "Generation: n + 1" for next commit
COMMIT_MSG=$(git show -s --format=%s | sed 's/Generation: \([0-9]\+\)/echo "Generation: $((\1 + 1))"/e')

git add .
git commit -S -m "${COMMIT_MSG}"
git push
