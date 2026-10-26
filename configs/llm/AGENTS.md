# llm

- No model downloads in `dot apply`: models are pulled on first use.
- Models are pinned: vLLM by hub commit (`model_revision`), ollama by manifest sha256 in `ollama-ensure-models.nu`.
- Models are not backed up. GPU access comes from `rocm/compute`.
