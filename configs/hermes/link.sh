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
  ln -sf "$(cd "${dir}" && pwd)" "${HOME}/.hermes/profiles/orchestrator/skills/${name}"
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

    # Widen Hermes' API read timeout for local slow CPU-only
    if ! grep -q '^HERMES_API_TIMEOUT=' "${HOME}/.hermes/.env" 2>/dev/null; then
        echo 'HERMES_API_TIMEOUT=1800' >> "${HOME}/.hermes/.env"
        chmod 600 "${HOME}/.hermes/.env"
    fi
fi

# Wallust-generated skin
"$(dirname "$(readlink -f "$0")")/../../scripts/generate-hermes-skin.py" || true
hermes skin use wallust || true

# Model routing:
#   Tier 1 (default):   claude-sonnet-5 via anthropic
#   Tier 2 (fallback):  z-ai/glm-5.3:US via Nous Portal (paid)
#   Tier 3 (fallback):  upstage/solar-pro4:free via Nous Portal (free tier)
#   Tier 4 (fallback):  vllm-rocm local GPU (cold-start, last resort)
#   Delegation:         z-ai/glm-5.3-flash:US via Nous (cheaper subagent work)

# Tier 1: default model
hermes config set model.default claude-sonnet-5
hermes config set model.provider anthropic

# Delegation: cheaper model for subagent work
hermes config set delegation.provider nous
hermes config set delegation.model "z-ai/glm-5.3-flash:US"

# vllm-rocm local provider (Tier 4, cold-started by configs/vllm/link.sh)
hermes config set providers.vllm-rocm.api "http://localhost:8000/v1"
hermes config set providers.vllm-rocm.default_model "mattbucci/gemma-4-12B-AWQ"
hermes config set providers.vllm-rocm.transport chat_completions

# Tier 2-4: fallback chain (Nous paid → Nous free → vllm local)
hermes config set fallback_providers '[{"provider":"nous","model":"z-ai/glm-5.3:US"},{"provider":"nous","model":"upstage/solar-pro4:free"},{"provider":"custom","model":"mattbucci/gemma-4-12B-AWQ","base_url":"http://localhost:8000/v1"}]'
