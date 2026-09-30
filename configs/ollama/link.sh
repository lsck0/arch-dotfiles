#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v ollama >/dev/null 2>&1; then
    exit 0
fi

set -ex

sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo ln -sfn "${PWD}/keep-alive.conf" /etc/systemd/system/ollama.service.d/keep-alive.conf
sudo systemctl daemon-reload
systemctl is-active --quiet ollama && sudo systemctl restart ollama || true

# typed-decision models behind /v1/systemone, formerly laya-serve; System One arrived in ollama 0.35
DECISION_MODELS=(nimble)
version=$(ollama --version 2>&1 | awk 'END {print $NF}')
if [[ $(vercmp "$version" 0.35.0) -lt 0 ]]; then
    echo "ollama: $version predates System One, not pulling ${DECISION_MODELS[*]}" >&2
    exit 0
fi
was_active=$(systemctl is-active ollama || true)
sudo systemctl start ollama
for ((i = 0; i < 30; i++)); do ollama list >/dev/null 2>&1 && break; sleep 1; done
for model in "${DECISION_MODELS[@]}"; do
    ollama pull "$model"
done
[[ "$was_active" == active ]] || sudo systemctl stop ollama
