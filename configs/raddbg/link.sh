#!/usr/bin/env bash

set -ex

sudo git clone https://github.com/EpicGamesExt/raddebugger.git /opt/raddebugger

sudo chown -R $(whoami):$(whoami) /opt/raddebugger

pushd /opt/raddebugger
git checkout v0.9.26-alpha
chmod +x build.sh
./build.sh raddbg
sudo ln -sf /opt/raddebugger/build/raddbg /usr/local/bin/raddbg
popd
