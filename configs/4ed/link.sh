#!/usr/bin/env bash

# 4ed is a C editor built from source. Guard on `git` (used for all three
# clones) so a rerun on a machine without git skips cleanly instead of
# `set -e` aborting on a missing binary.
if ! command -v git >/dev/null 2>&1; then
    echo "configs/4ed/link.sh: git not installed, skipping" >&2
    exit 0
fi

sudo git clone https://github.com/4coder-archive/4coder.git /opt/4ed/code
sudo git clone https://github.com/4coder-archive/4coder-non-source.git /opt/4ed/4coder-non-source
sudo git clone https://github.com/4coder-archive/4coder_fleury.git /opt/4ed/code/custom/fleury

sudo chown -R $(whoami):$(whoami) /opt/4ed

export C_INCLUDE_PATH="/usr/include/freetype2:$C_INCLUDE_PATH"
export CPLUS_INCLUDE_PATH="/usr/include/freetype2:$CPLUS_INCLUDE_PATH"
cd /opt/4ed/code               && ./bin/build-linux.sh
cd /opt/4ed/code/custom/fleury && ./build_linux.sh
cd /opt/4ed/code               && ./bin/package-linux.sh

sudo ln -sf /opt/4ed/current_dist_demo_x64/4coder/4ed /usr/local/bin/4ed
