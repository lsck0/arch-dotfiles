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
# venv python must match the minor version that owns python-pytorch-opt-rocm, so system-site-packages exposes the rocm torch.
LAYA_PYTHON_VERSION=3.14

# gfx1101 is native to ROCm 7.2, so no HSA_OVERRIDE_GFX_VERSION is needed.
# fresh venv: --allow-existing would keep a shadowing cuda torch already in .venv.
rm -rf "${LAYA_PROJECT}/.venv"
uv venv --system-site-packages --python "$LAYA_PYTHON_VERSION" "${LAYA_PROJECT}/.venv"
# exclude torch so it resolves to the system rocm build instead of a pip cuda wheel.
uv pip install --python "${LAYA_PROJECT}/.venv" --excludes "${PWD}/uv-excludes.txt" "laya[serve]"

# hard gate: refuse to ship cpu/cuda torch. rocm means hip set and cuda_available true.
if ! "${LAYA_PROJECT}/.venv/bin/python" -c 'import torch,sys; sys.exit(0 if (torch.version.hip and torch.cuda.is_available()) else 1)'; then
    set +x
    echo "laya: venv torch is not rocm (hip/cuda_available); leaving service uninstalled" >&2
    "${LAYA_PROJECT}/.venv/bin/python" -c 'import torch; print("laya: got", torch.__version__, "hip", torch.version.hip, "cuda", torch.cuda.is_available())' >&2 || true
    exit 1
fi

install -Dm644 "${PWD}/laya-serve.service" "$HOME/.config/systemd/user/laya-serve.service"
systemctl --user daemon-reload
# do not enable/start: toggle-laya.sh controls it.
