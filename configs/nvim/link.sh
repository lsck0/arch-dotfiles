#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v nvim >/dev/null 2>&1; then
    exit 0
fi

set -ex

ln -sfn "${PWD}" "$HOME/.config/nvim"

nvim --headless "+Lazy! sync" +MasonToolsInstallSync +qa

# minuet-ai (Copilot-style completion) runs a small local ollama FIM model
MINUET_MODEL="qwen2.5-coder:0.5b"
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
    ollama list 2>/dev/null | grep -q "^${MINUET_MODEL} " \
        || ollama pull "${MINUET_MODEL}" || echo "minuet: ${MINUET_MODEL} pull failed" >&2
    if [ "${ollama_was_active}" -eq 0 ]; then
        sudo systemctl stop ollama
    fi
fi
