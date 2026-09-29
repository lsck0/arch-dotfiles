# laya

Local `laya-serve` server for [laya](https://pypi.org/project/laya/) on
`LAYA_PORT=8100` (8000 is vllm-rocm).

- `link.sh` no-ops unless `rocminfo` reports a `gfx` agent.
- It rebuilds `~/projects/laya/.venv` with system site packages and torch
  excluded, so torch is the system `python-pytorch-opt-rocm` build. The venv
  python (3.14) must match that package's python.
- It fails and skips the unit if the venv torch is not ROCm.
- The user unit is installed but not enabled; start and stop it with
  `toggles/toggle-laya.sh`.
