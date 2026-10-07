#!/usr/bin/env bash
# lazy model provisioning, run on first ollama/hermes use, not during config.sh
# one source for every ollama model: System One and hermes' cpu fallback
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v ollama >/dev/null 2>&1; then
    exit 0
fi

set -e

# the typed-decision models behind /v1/systemone (ollama 0.35+)
MODELS=()
version=$(ollama --version 2>&1 | awk 'END {print $NF}')
if [[ $(vercmp "$version" 0.35.0) -lt 0 ]]; then
    echo "ollama: $version predates System One, not pulling nimble" >&2
else
    MODELS+=(nimble)
fi

# start the on-demand service only if idle, and leave it as we found it, also when a pull fails under set -e
was_active=0
systemctl is-active --quiet ollama && was_active=1
trap '((was_active)) || systemctl stop ollama' EXIT
((was_active)) || systemctl start ollama
for ((i = 0; i < 30; i++)); do ollama list >/dev/null 2>&1 && break; sleep 1; done

# pulls only what is missing; show fails exactly for an absent model
for model in "${MODELS[@]}"; do
    ollama show "$model" >/dev/null 2>&1 || ollama pull "$model"
done

# hermes' cpu fallback: ollama's default num_ctx is small regardless of the model
if ! ollama list | grep -q '^llama3.1-64k'; then
    ollama pull llama3.1:8b
    tmp_modelfile="$(mktemp)"
    printf 'FROM llama3.1:8b\nPARAMETER num_ctx 65536\n' >"${tmp_modelfile}"
    ollama create llama3.1-64k -f "${tmp_modelfile}"
    rm -f "${tmp_modelfile}"
    ollama rm llama3.1:8b
fi
