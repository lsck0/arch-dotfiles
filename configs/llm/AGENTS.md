# llm

- Models arrive without a manual step: vLLM pulls its model on first start; `llm/ollama` runs `ollama-ensure-models`
  once per pin set (a stamp under `$XDG_STATE_HOME/ollama-models`), only where a GPU has VRAM; `llm/comfyui` downloads
  its image and 3D checkpoints in its `models` step, only with an AMD GPU of 12 GiB or more; `llm/alpaca` fetches
  whisper's speech model.
- Models are pinned: vLLM by hub commit (`model_revision`), ollama by manifest sha256 in `ollama-ensure-models.nu`,
  ComfyUI by hub commit and file sha256 (`MODELS`). ComfyUI's venv is `uv.lock`'s, torch from the ROCm index.
- `llm/comfyui` is a user service: the editor at http://127.0.0.1:8188 (socket-activated, stops 10 minutes after the
  last tab closes), outputs in `~/pictures/comfyui`.
- Models are not backed up. GPU access comes from `rocm/compute`.
