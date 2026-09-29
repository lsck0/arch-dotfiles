#!/usr/bin/env bash
# Install JAI + the Jails language server from the newest beta zip in ~/sync (the beta is invite-only, no public URL).

set -euo pipefail

SYNC_DIR="${HOME}/sync"
JAI_DIR="${HOME}/.jai"

zip_path=$(find "$SYNC_DIR" -maxdepth 1 -name 'jai-*.zip' | sort -V | tail -n 1)
if [[ -z "$zip_path" ]]; then
    echo "no jai-*.zip in ${SYNC_DIR}" >&2
    exit 1
fi

rm -rf "$JAI_DIR"
mkdir -p "$JAI_DIR"
# the zip holds a single top-level jai/ dir
unzip -q "$zip_path" -d "$JAI_DIR"
mv "$JAI_DIR"/jai/* "$JAI_DIR"/
rmdir "$JAI_DIR"/jai

git clone --recursive https://github.com/SogoCZE/Jails.git "$JAI_DIR"/jails
pushd "$JAI_DIR"/jails
"$JAI_DIR"/bin/jai-linux build.jai
popd

ln -sfn "$JAI_DIR"/jails/bin/jails "$JAI_DIR"/bin/jails
