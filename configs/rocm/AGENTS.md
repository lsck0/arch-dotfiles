# rocm

Extends the root `AGENTS.md`. AMD GPU compute stack.

## Modules

- `compute`: ROCm/HIP for interactive compute (python-pytorch-opt-rocm, Blender HIP, ollama-rocm); puts the user in
  the render and video groups (only when an AMD GPU is present).

## Conventions

- Group membership (render, video) needs a re-login to take effect.
- Consumers of this stack live elsewhere: `llm/vllm`, `creating/blender`. This group provides the GPU access, not the apps.
