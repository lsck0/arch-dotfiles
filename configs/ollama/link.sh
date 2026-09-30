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

# minuet's fim model for nvim, plus the typed-decision models behind /v1/systemone (ollama 0.35+)
MODELS=(qwen2.5-coder:0.5b)
version=$(ollama --version 2>&1 | awk 'END {print $NF}')
if [[ $(vercmp "$version" 0.35.0) -lt 0 ]]; then
    echo "ollama: $version predates System One, not pulling nimble" >&2
else
    MODELS+=(nimble)
fi
was_active=$(systemctl is-active ollama || true)
sudo systemctl start ollama
for ((i = 0; i < 30; i++)); do ollama list >/dev/null 2>&1 && break; sleep 1; done
for model in "${MODELS[@]}"; do
    ollama pull "$model" || echo "ollama: pulling $model failed" >&2
done
[[ "$was_active" == active ]] || sudo systemctl stop ollama
