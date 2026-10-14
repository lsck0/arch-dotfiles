# llm

Extends the root `AGENTS.md`. Local LLM runtimes and frontends.

## Modules

- `alpaca`: a flatpak chat frontend, configured only once installed (seeds its sqlite db).
- `ollama`: the local model server; models are pulled lazily on first use, never during `dot apply`.
- `vllm`: the ROCm vLLM build, pinned by release and rocm tag under a resolvable index; model, revision and vram share
  are options (the share detected from the card's vram).
- `tools`: llmfit and heretic (packages only).

## Conventions

- No model downloads in `dot apply`: models are GB-scale and pulled on first use. Keep the install path off that.
- Models are pinned like packages: the vLLM model by hub commit (the `model_revision` option), the ollama
  models by manifest sha256 in `ollama-ensure-models.nu`, checked before and after the pull. Bump them by hand.
- Models and weights are re-downloadable and excluded from borg (see root backup model).
- vLLM is a ROCm workload; the GPU and group access come from `rocm/compute`.
