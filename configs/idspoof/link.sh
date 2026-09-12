#!/usr/bin/env bash

if ! command -v git >/dev/null 2>&1 || ! command -v go >/dev/null 2>&1; then
    exit 0
fi

set -ex

git clone https://github.com/NubleX/ID-Spoofer.git
cd ID-Spoofer/idspoof
make build
sudo cp bin/idspoof /usr/local/bin/
cd ..
rm -rf ID-Spoofer
