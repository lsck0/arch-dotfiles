#!/usr/bin/env bash

VLLM_PREFIX=/opt/vllm
VLLM_WHEELS_URL=https://wheels.vllm.ai/rocm/
VLLM_VERSION=0.30.0+rocm723
VLLM_OMNI_VERSION=0.30.0
# rocm wheels are cp312 only
VLLM_PYTHON_VERSION=3.12

# /etc/profile.d/rocm.sh only covers login shells
PATH="$PATH:/opt/rocm/bin"
command -v rocminfo >/dev/null 2>&1 || exit 0
# rocminfo errors without a usable amd gpu, that is the skip case
if ! rocminfo 2>/dev/null | grep -q '^Agent [0-9]*.*$' || ! rocminfo 2>/dev/null | grep -q 'gfx[0-9a-f]\{3,\}'; then
    exit 0
fi

# root-owned, root builds it: the service runs this venv, so no user may write into it; earlier runs left it the user's
install -d -o root -g root -m755 "$VLLM_PREFIX"
if [[ -n "$(find "$VLLM_PREFIX" ! -user root -print -quit)" ]]; then
    chown -R root:root "$VLLM_PREFIX"
fi
export UV_PYTHON_INSTALL_DIR="$VLLM_PREFIX/python"
uv venv --allow-existing --python "$VLLM_PYTHON_VERSION" "$VLLM_PREFIX/venv"
# mooncake's bundled glog clashes with system glog and aborts the import
uv pip install --python "$VLLM_PREFIX/venv" --extra-index-url "$VLLM_WHEELS_URL" \
    --excludes uv-excludes.txt "vllm==$VLLM_VERSION" "vllm-omni==$VLLM_OMNI_VERSION"
uv pip uninstall --python "$VLLM_PREFIX/venv" -r uv-excludes.txt

# torch RUNPATH is $ORIGIN, so the stub is found beside libtorch
torch_lib_dir="$("$VLLM_PREFIX/venv/bin/python" -c 'import sysconfig; print(sysconfig.get_path("platlib"))')/torch/lib"
stub_build_dir="$(mktemp -d)"
cc -shared -fPIC -O2 -Wall -Werror -Wl,-soname,libmpi_cxx.so.40 \
    -o "$stub_build_dir/libmpi_cxx.so.40" mpi-cxx-stub.c
install -m755 "$stub_build_dir/libmpi_cxx.so.40" "$torch_lib_dir/libmpi_cxx.so.40"
rm -rf "$stub_build_dir"

install -Dm755 vllm-wait-ready.sh /usr/local/bin/vllm-wait-ready
unit_install vllm-proxy.service vllm.service vllm.socket
systemctl enable --now vllm.socket
