# laya

Local server for [laya](https://pypi.org/project/laya/), a non-autoregressive
typed-decision model: one forward pass returns a choice plus a calibrated
probability, no text generation. Ships the `laya-serve` FastAPI/uvicorn server
exposing `/health` and a predict API.

## Port

Runs on `LAYA_PORT=8100`. Port 8000 is taken by vllm-rocm.

## ROCm gated

`link.sh` mirrors `configs/vllm/link.sh`: it no-ops unless `rocminfo` is present
and reports a `gfx` agent. Only machines that do local GPU inference get it.

## ROCm torch

The laya project at `~/projects/laya` is a uv project whose default venv resolves
to a CUDA torch wheel (`+cu130`), useless on AMD. `link.sh` fixes this by
recreating the venv with `uv venv --system-site-packages --python 3.14` and
installing `laya[serve]` with torch excluded (`uv-excludes.txt`). torch then
resolves to the system `python-pytorch-opt-rocm` build (ROCm 7.2, gfx1101 native,
no `HSA_OVERRIDE_GFX_VERSION`). The venv python minor version must match the one
that owns `python-pytorch-opt-rocm` (3.14) for system-site-packages to expose it.

`link.sh` hard-gates on `torch.version.hip` set and `torch.cuda.is_available()`
true; if the venv torch is not ROCm it leaves the service uninstalled and errors.

## Toggle controlled

`link.sh` installs the `laya-serve.service` user unit and reloads the daemon but
does not enable or start it. `toggles/toggle-laya.sh` starts/stops it via
`systemctl --user`. Under ROCm, `/health` reports `device: cuda` (HIP presents as
cuda in the torch API) with no cpu fallbacks.
