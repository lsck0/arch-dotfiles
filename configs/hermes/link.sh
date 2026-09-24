#!/usr/bin/env bash

if ! command -v hermes >/dev/null 2>&1; then
    exit 0
fi

set -ex

if [ ! -d "${HOME}/.hermes/profiles/orchestrator" ]; then
    hermes profile create orchestrator --clone --description "Orchestrator. Not for interactive chat."
fi
HERMES_HOME="${HOME}/.hermes/profiles/orchestrator" hermes config set compression.threshold_tokens 500000
hermes profile alias orchestrator --name hermes-orchestrator

# Sync skills into the orchestrator profile too
mkdir -p "${HOME}/.hermes/profiles/orchestrator/skills"
for dir in "$(dirname "$0")"/../../skills/l-*/; do
  name=$(basename "${dir}")
  ln -sfn "$(cd "${dir}" && pwd)" "${HOME}/.hermes/profiles/orchestrator/skills/${name}"
done
find "${HOME}/.hermes/profiles/orchestrator/skills" -maxdepth 1 -xtype l -name 'l-*' -delete

# Local Ollama as an available Hermes model source
if command -v ollama >/dev/null 2>&1; then
    ollama_was_active=1
    if ! systemctl is-active --quiet ollama; then
        ollama_was_active=0
        sudo systemctl start ollama
        for _ in $(seq 1 30); do
            curl -fs http://localhost:11434/api/version >/dev/null 2>&1 && break
            sleep 1
        done
    fi

    if ! ollama list 2>/dev/null | grep -q '^llama3.1-64k'; then
        # Ollama's default num_ctx is small regardless of a model's true max; so make it bigger
        ollama pull llama3.1:8b
        tmp_modelfile="$(mktemp)"
        printf 'FROM llama3.1:8b\nPARAMETER num_ctx 65536\n' > "${tmp_modelfile}"
        ollama create llama3.1-64k -f "${tmp_modelfile}"
        rm -f "${tmp_modelfile}"
        ollama rm llama3.1:8b 2>/dev/null || true
    fi

    if [ "${ollama_was_active}" -eq 0 ]; then
        sudo systemctl stop ollama
    fi

    hermes config set providers.ollama-local.api "http://localhost:11434/v1"
    hermes config set providers.ollama-local.default_model "llama3.1-64k"
    hermes config set providers.ollama-local.context_length 65536
    hermes config set providers.ollama-local.transport chat_completions

    # Widen Hermes' API read timeout for slow local CPU-only backends.
    if ! grep -q '^HERMES_API_TIMEOUT=' "${HOME}/.hermes/.env" 2>/dev/null; then
        echo 'HERMES_API_TIMEOUT=1800' >> "${HOME}/.hermes/.env"
        chmod 600 "${HOME}/.hermes/.env"
    fi
fi

# Wallust-generated skin
hermes config set display.interface tui
"$(dirname "$(readlink -f "$0")")/../wallust/scripts/generate-hermes-skin.py" || true
hermes skin use wallust || true

# Model routing:
#   Tier 1 (default):   claude-sonnet-5 via anthropic
#   Tier 2 (fallback):  free Nous Portal models (no per-token cost)
#   Tier 3 (fallback):  vllm-rocm local GPU (cold-started by configs/vllm)
#   Tier 4 (fallback):  ollama-local CPU (last resort)
#   Delegation:         a free Nous model (cheap subagent work, no cost)

# Tier 1: default model, anthropic only
hermes config set model.default claude-sonnet-5
hermes config set model.provider anthropic

# Delegation: free Nous model for subagent work
hermes config set delegation.provider nous
hermes config set delegation.model "meituan/longcat-2.0:free"

# vllm-rocm local provider (Tier 3, cold-started by configs/vllm/link.sh)
hermes config set providers.vllm-rocm.api "http://localhost:8000/v1"
hermes config set providers.vllm-rocm.default_model "mattbucci/gemma-4-12B-AWQ"
hermes config set providers.vllm-rocm.transport chat_completions

# Fallback chain: free Nous models, then local GPU (vllm), then local CPU (ollama)
hermes config set fallback_providers '[{"provider":"nous","model":"meituan/longcat-2.0:free"},{"provider":"nous","model":"poolside/laguna-s-2.1:free"},{"provider":"vllm-rocm","model":"mattbucci/gemma-4-12B-AWQ"},{"provider":"ollama-local","model":"llama3.1-64k"}]'
