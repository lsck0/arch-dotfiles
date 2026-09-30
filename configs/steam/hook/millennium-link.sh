#!/usr/bin/env bash
# millennium loads by replacing libXtst in steam's runtime dirs, which exist only after steam's first run

set -euo pipefail

STEAM="${HOME}/.local/share/Steam"
LIB=/usr/lib/millennium

[[ -d "${STEAM}/ubuntu12_32" && -d "${STEAM}/ubuntu12_64" && -d "$LIB" ]] || exit 0

ln -sfn "${LIB}/libmillennium_bootstrap_x86.so" "${STEAM}/ubuntu12_32/libXtst.so.6"
ln -sfn "${LIB}/libmillennium_bootstrap_hhx64.so" "${STEAM}/ubuntu12_64/libXtst.so.6"
ln -sfn "${LIB}/libmillennium_hhx64.so" "${STEAM}/ubuntu12_64/libmillennium_hhx64.so"
