#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# /etc/profile.d/rocm.sh puts rocm on PATH only for login shells, and config.sh may run outside one
PATH="${PATH}:/opt/rocm/bin"
if ! command -v rocminfo >/dev/null 2>&1; then
    exit 0
fi

if ! rocminfo 2>/dev/null | grep -q '^Agent [0-9]*.*$' || ! rocminfo 2>/dev/null | grep -q 'gfx[0-9a-f]\{3,\}'; then
    exit 0
fi

set -e

VLLM_PREFIX=/opt/vllm
VLLM_WHEELS_URL=https://wheels.vllm.ai/rocm/
VLLM_VERSION=0.30.0+rocm723
VLLM_OMNI_VERSION=0.30.0
# rocm wheels are cp312 only
VLLM_PYTHON_VERSION=3.12

sudo env UV_PYTHON_INSTALL_DIR="${VLLM_PREFIX}/python" \
    uv venv --allow-existing --python "$VLLM_PYTHON_VERSION" "${VLLM_PREFIX}/venv"
# mooncake's bundled glog clashes with system glog and aborts the import
sudo env UV_PYTHON_INSTALL_DIR="${VLLM_PREFIX}/python" \
    uv pip install --python "${VLLM_PREFIX}/venv" --extra-index-url "$VLLM_WHEELS_URL" \
    --excludes "${PWD}/uv-excludes.txt" "vllm==${VLLM_VERSION}" "vllm-omni==${VLLM_OMNI_VERSION}"
sudo uv pip uninstall --python "${VLLM_PREFIX}/venv" -r "${PWD}/uv-excludes.txt"

# torch RUNPATH is $ORIGIN, so the stub is found beside libtorch
torch_lib_dir="$("${VLLM_PREFIX}/venv/bin/python" -c 'import sysconfig; print(sysconfig.get_path("platlib"))')/torch/lib"
stub_build_dir="$(mktemp -d)"
cc -shared -fPIC -O2 -Wall -Werror -Wl,-soname,libmpi_cxx.so.40 \
    -o "${stub_build_dir}/libmpi_cxx.so.40" "${PWD}/mpi-cxx-stub.c"
sudo install -m 755 "${stub_build_dir}/libmpi_cxx.so.40" "${torch_lib_dir}/libmpi_cxx.so.40"
rm -rf "$stub_build_dir"

chmod 755 "${PWD}/vllm-wait-ready.sh"

sed "s|@HOME@|$HOME|" "${PWD}/vllm-proxy.service" | sudo tee /etc/systemd/system/vllm-proxy.service >/dev/null
sudo cp "${PWD}/vllm.service" /etc/systemd/system/vllm.service
sudo cp "${PWD}/vllm.socket" /etc/systemd/system/vllm.socket

sudo systemctl daemon-reload
sudo systemctl enable --now vllm.socket
