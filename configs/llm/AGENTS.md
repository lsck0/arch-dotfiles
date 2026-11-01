# llm

- Models arrive without a manual step: vLLM pulls its model on first start; `llm/ollama` runs `ollama-ensure-models`
  once per pin set (a stamp under `$XDG_STATE_HOME/ollama-models`), only where a GPU has VRAM; `llm/alpaca` fetches
  whisper's speech model.
- Models are pinned: vLLM by hub commit (`model_revision`), ollama by manifest sha256 in `ollama-ensure-models.nu`.
- Models are not backed up. GPU access comes from `rocm/compute`.
