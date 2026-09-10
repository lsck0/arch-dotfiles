#!/usr/bin/env bash

set -ex

git clone https://github.com/NubleX/ID-Spoofer.git
cd ID-Spoofer/idspoof
make build
sudo cp bin/idspoof /usr/local/bin/
cd ..
rm -rf ID-Spoofer
