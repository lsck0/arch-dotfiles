#!/bin/env bash

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
