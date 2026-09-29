#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v rocminfo >/dev/null 2>&1; then
    exit 0
fi

if ! rocminfo 2>/dev/null | grep -q '^Agent [0-9]*.*$' || ! rocminfo 2>/dev/null | grep -q 'gfx[0-9a-f]\{3,\}'; then
    exit 0
fi

set -ex

LAYA_PROJECT="$HOME/projects/laya"
# must match python-pytorch-opt-rocm's python so the venv sees system torch
LAYA_PYTHON_VERSION=3.14

# fresh venv: an old one may hold a shadowing cuda torch
rm -rf "${LAYA_PROJECT}/.venv"
uv venv --system-site-packages --python "$LAYA_PYTHON_VERSION" "${LAYA_PROJECT}/.venv"
# torch excluded so the system rocm build wins over a cuda wheel
uv pip install --python "${LAYA_PROJECT}/.venv" --excludes "${PWD}/uv-excludes.txt" "laya[serve]"

# refuse cpu/cuda torch
if ! "${LAYA_PROJECT}/.venv/bin/python" -c 'import torch,sys; sys.exit(0 if (torch.version.hip and torch.cuda.is_available()) else 1)'; then
    set +x
    echo "laya: venv torch is not rocm (hip/cuda_available); leaving service uninstalled" >&2
    "${LAYA_PROJECT}/.venv/bin/python" -c 'import torch; print("laya: got", torch.__version__, "hip", torch.version.hip, "cuda", torch.cuda.is_available())' >&2 || true
    exit 1
fi

install -Dm644 "${PWD}/laya-serve.service" "$HOME/.config/systemd/user/laya-serve.service"
systemctl --user daemon-reload
# toggle-laya.sh starts it
