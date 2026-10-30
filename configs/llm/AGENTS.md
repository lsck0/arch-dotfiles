# llm

- No model downloads in `dot apply`: vLLM pulls its model on first start, ollama's come from running
  `ollama-ensure-models`.
- Models are pinned: vLLM by hub commit (`model_revision`), ollama by manifest sha256 in `ollama-ensure-models.nu`.
- Models are not backed up. GPU access comes from `rocm/compute`.
