#!/usr/bin/env bash

hermes_default="${HOME}/.hermes"
hermes_orchestrator="${HOME}/.hermes/profiles/orchestrator"

if [ ! -d "${hermes_orchestrator}" ]; then
    hermes profile create orchestrator --clone --description "Orchestrator. Not for interactive chat."
    hermes profile alias orchestrator --name hermes-orchestrator
fi

# skills into the orchestrator profile too
mkdir -p "${hermes_orchestrator}/skills"
for dir in $DOTFILES/skills/l-*/; do
    name=$(basename "${dir}")
    ln -sfn "$(cd "${dir}" && pwd)" "${hermes_orchestrator}/skills/${name}"
done
find "${hermes_orchestrator}/skills" -maxdepth 1 -xtype l -name 'l-*' -delete

# local ollama as a model source; llama3.1-64k is built lazily by ollama-ensure-models,
# a fallback-only route here, so it need not exist yet at config time
have_ollama=0
command -v ollama >/dev/null 2>&1 && have_ollama=1

# skin lives in the default profile, wallpaper switches rewrite only that
HERMES_HOME="${hermes_default}" $DOTFILES/configs/base/wallust/scripts/generate-hermes-skin.py
mkdir -p "${hermes_orchestrator}/skins"
ln -sfn "${hermes_default}/skins/wallust.yaml" "${hermes_orchestrator}/skins/wallust.yaml"

# --clone snapshots the default profile once, so configure both
for hermes_home in "${hermes_default}" "${hermes_orchestrator}"; do
    export HERMES_HOME="${hermes_home}"

    # slow cpu-only backends need a long read timeout
    if [ "${have_ollama}" -eq 1 ] && ! grep -qs '^HERMES_API_TIMEOUT=' "${hermes_home}/.env"; then
        echo 'HERMES_API_TIMEOUT=1800' >> "${hermes_home}/.env"
        chmod 600 "${hermes_home}/.env"
    fi

    # one interpreter instead of a hermes launch per key; set_config_value coerces like `hermes config set`
    HAVE_OLLAMA="${have_ollama}" ORCHESTRATOR="${hermes_orchestrator}" /opt/hermes-agent/venv/bin/python - <<'PY'
import os
from hermes_cli.config import set_config_value
from hermes_cli.skin_cmd import _use
settings = []
if os.environ["HAVE_OLLAMA"] == "1":
    settings += [
        ("providers.ollama-local.api", "http://localhost:11434/v1"),
        ("providers.ollama-local.default_model", "llama3.1-64k"),
        ("providers.ollama-local.context_length", "65536"),
        ("providers.ollama-local.transport", "chat_completions"),
    ]
settings += [
    ("display.interface", "tui"),
    # routing: anthropic, then free nous, then vllm gpu, then ollama cpu
    ("model.default", "claude-sonnet-5"),
    ("model.provider", "anthropic"),
    ("delegation.provider", "nous"),
    ("delegation.model", "meituan/longcat-2.0:free"),
    # cold-started by configs/llm/vllm
    ("providers.vllm-rocm.api", "http://localhost:8000/v1"),
    ("providers.vllm-rocm.default_model", "mattbucci/gemma-4-12B-AWQ"),
    ("providers.vllm-rocm.transport", "chat_completions"),
    ("fallback_providers", '[{"provider":"nous","model":"meituan/longcat-2.0:free"},{"provider":"nous","model":"poolside/laguna-s-2.1:free"},{"provider":"vllm-rocm","model":"mattbucci/gemma-4-12B-AWQ"},{"provider":"ollama-local","model":"llama3.1-64k"}]'),
]
if os.environ["HERMES_HOME"] == os.environ["ORCHESTRATOR"]:
    settings += [("compression.threshold_tokens", "500000")]
for key, value in settings:
    set_config_value(key, value)
_use("wallust")
PY

    # awake only while an agent works, same guard as claude code; pre-approved so no first-use prompt
    guard="${HOME}/.config/idle-guards/agent-guard.sh"
    if [ -x "${guard}" ]; then
        GUARD="${guard}" /opt/hermes-agent/venv/bin/python - <<'PY'
import os
from hermes_cli.config import load_config, save_config
from agent.shell_hooks import _record_approval
guard = os.environ["GUARD"]
# pre/post_llm_call bracket each turn (post after its tool loop); on_session_end covers an aborted one
events = {"pre_llm_call": "turn-start", "post_llm_call": "turn-end", "on_session_end": "turn-end",
          "subagent_start": "subagent-start", "subagent_stop": "subagent-stop"}
config = load_config()
hooks = config.setdefault("hooks", {})
for event, action in events.items():
    command = f"{guard} {action}"
    hooks[event] = [h for h in hooks.get(event) or [] if "agent-guard" not in str(h.get("command", ""))] + [{"command": command}]
    _record_approval(event, command)
save_config(config, merge_existing=True)
PY
    fi
done
unset HERMES_HOME
