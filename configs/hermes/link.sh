#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v hermes >/dev/null 2>&1; then
    exit 0
fi

set -e

hermes_default="${HOME}/.hermes"
hermes_orchestrator="${HOME}/.hermes/profiles/orchestrator"

if [ ! -d "${hermes_orchestrator}" ]; then
    hermes profile create orchestrator --clone --description "Orchestrator. Not for interactive chat."
fi
hermes profile alias orchestrator --name hermes-orchestrator

# skills into the orchestrator profile too
mkdir -p "${hermes_orchestrator}/skills"
for dir in ../../skills/l-*/; do
    name=$(basename "${dir}")
    ln -sfn "$(cd "${dir}" && pwd)" "${hermes_orchestrator}/skills/${name}"
done
find "${hermes_orchestrator}/skills" -maxdepth 1 -xtype l -name 'l-*' -delete

# local ollama as a model source
have_ollama=0
if command -v ollama >/dev/null 2>&1; then
    have_ollama=1
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
        # ollama's default num_ctx is small regardless of the model
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
fi

# default HERMES_HOME so the skin lands in the default profile, wallpaper switches rewrite only that one
HERMES_HOME="${hermes_default}" ../wallust/scripts/generate-hermes-skin.py || true
mkdir -p "${hermes_orchestrator}/skins"
ln -sfn "${hermes_default}/skins/wallust.yaml" "${hermes_orchestrator}/skins/wallust.yaml"

# --clone copied the default profile before any of this was set, so configure both every run
for hermes_home in "${hermes_default}" "${hermes_orchestrator}"; do
    export HERMES_HOME="${hermes_home}"

    if [ "${have_ollama}" -eq 1 ]; then
        hermes config set providers.ollama-local.api "http://localhost:11434/v1"
        hermes config set providers.ollama-local.default_model "llama3.1-64k"
        hermes config set providers.ollama-local.context_length 65536
        hermes config set providers.ollama-local.transport chat_completions

        # slow cpu-only backends need a long read timeout
        if ! grep -q '^HERMES_API_TIMEOUT=' "${hermes_home}/.env" 2>/dev/null; then
            echo 'HERMES_API_TIMEOUT=1800' >> "${hermes_home}/.env"
            chmod 600 "${hermes_home}/.env"
        fi
    fi

    hermes config set display.interface tui
    hermes skin use wallust || true

    # routing: anthropic, then free nous, then vllm gpu, then ollama cpu
    hermes config set model.default claude-sonnet-5
    hermes config set model.provider anthropic

    hermes config set delegation.provider nous
    hermes config set delegation.model "meituan/longcat-2.0:free"

    # cold-started by configs/vllm
    hermes config set providers.vllm-rocm.api "http://localhost:8000/v1"
    hermes config set providers.vllm-rocm.default_model "mattbucci/gemma-4-12B-AWQ"
    hermes config set providers.vllm-rocm.transport chat_completions

    hermes config set fallback_providers '[{"provider":"nous","model":"meituan/longcat-2.0:free"},{"provider":"nous","model":"poolside/laguna-s-2.1:free"},{"provider":"vllm-rocm","model":"mattbucci/gemma-4-12B-AWQ"},{"provider":"ollama-local","model":"llama3.1-64k"}]'
done
unset HERMES_HOME

HERMES_HOME="${hermes_orchestrator}" hermes config set compression.threshold_tokens 500000
