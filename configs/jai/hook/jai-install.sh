#!/usr/bin/env bash
# jai + jails from the newest ~/sync beta zip; runs on every ~/sync change, so no-op unless the zip is new

set -euo pipefail

SYNC_DIR="${HOME}/sync"
JAI_DIR="${HOME}/.jai"
STAMP="${JAI_DIR}/.installed-from"

zip_path=$(find "$SYNC_DIR" -maxdepth 1 -name 'jai-*.zip' 2>/dev/null | sort -V | tail -n 1)
if [[ -z "$zip_path" ]]; then
    exit 0
fi
if [[ -f "$STAMP" && "$(cat "$STAMP")" == "$(basename "$zip_path")" ]]; then
    exit 0
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
basename "$zip_path" >"$STAMP"
