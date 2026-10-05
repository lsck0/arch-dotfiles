#!/usr/bin/env bash
# jai + jails from the newest ~/sync beta zip; no-op unless the zip is new, link.sh reruns it for later betas

set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../../../scripts/lib/user-hook.sh"
source "$(dirname "$(readlink -f "$0")")/../../../scripts/lib/fetch.sh"

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

# built and run as luca, so a pinned commit; bump by hand
fetch_git_pinned https://github.com/SogoCZE/Jails.git 42fa76c816ad34c9f24a4bde586d145c992dc860 "$JAI_DIR"/jails
pushd "$JAI_DIR"/jails
"$JAI_DIR"/bin/jai-linux build.jai
popd

ln -sfn "$JAI_DIR"/jails/bin/jails "$JAI_DIR"/bin/jails
basename "$zip_path" >"$STAMP"
user_hook_retire jai-install
