#!/usr/bin/env bash

set -ex

if [ ! -d "${HOME}/.hermes/profiles/orchestrator" ]; then
    hermes profile create orchestrator --clone --description "Orchestrator. Not for interactive chat."
fi

hermes profile alias orchestrator --name hermes-orchestrator

HERMES_HOME="${HOME}/.hermes/profiles/orchestrator" hermes config set compression.threshold_tokens 100000

# Sync skills into the orchestrator profile too — `hermes profile create
# --clone` only snapshots skills/ once at creation time, it does NOT stay
# live-mirrored to ~/.hermes/skills/ afterward. Without this, the profile
# silently drifts stale (missing skills added later, holding dangling
# symlinks to skills since renamed/removed) exactly like a second,
# unsynced copy of skills/link.sh's target would.
mkdir -p "${HOME}/.hermes/profiles/orchestrator/skills"
for dir in "$(dirname "$0")"/../../skills/l-*/; do
  name=$(basename "${dir}")
  ln -sf "$(cd "${dir}" && pwd)" "${HOME}/.hermes/profiles/orchestrator/skills/${name}"
done
# Sweep dangling symlinks left over from a since-renamed/removed skill —
# `ln -sf` above only ever adds/updates, never removes.
find "${HOME}/.hermes/profiles/orchestrator/skills" -maxdepth 1 -xtype l -name 'l-*' -delete

# Local Ollama as an available Hermes model source (default profile). Not the
# default model — switch to it per-session with `/model llama3.1-64k` or
# `hermes -m llama3.1-64k --provider ollama-local`. CPU-only inference on this
# machine (no dGPU): a full agentic turn (~14K token system prompt + tools)
# takes tens of minutes at ~8 tok/s prefill, so this is for offline/privacy
# use, not day-to-day driving. The systemd service is left disabled/stopped
# day-to-day (start on demand with `sudo systemctl start ollama`); this
# script briefly starts it if needed to check/build the model, then restores
# whatever state it was actually in before the script ran.
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
        # Ollama's default num_ctx is small regardless of a model's true max;
        # Hermes requires >=64K context for agentic tool-calling sessions, so
        # bake a bumped-context variant. llama3.1:8b has a real 128K window
        # (unlike e.g. qwen2.5-coder:7b, which caps at 32K and can't be used).
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

    # Widen Hermes' API read timeout for slow CPU-only local prefill (env var,
    # not a config.yaml key — must live in .env).
    if ! grep -q '^HERMES_API_TIMEOUT=' "${HOME}/.hermes/.env" 2>/dev/null; then
        echo 'HERMES_API_TIMEOUT=1800' >> "${HOME}/.hermes/.env"
        chmod 600 "${HOME}/.hermes/.env"
    fi
fi
