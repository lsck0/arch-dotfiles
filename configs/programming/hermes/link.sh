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

# skin lives in the default profile, wallpaper switches rewrite only that. a fresh install has no palette yet: config.sh
# applies the first theme after every link.sh, and that switch writes the skin
if [[ -e "$HOME/.cache/wal/colors.json" ]]; then
    HERMES_HOME="${hermes_default}" $DOTFILES/configs/core/wallust/scripts/generate-hermes-skin.py
fi
mkdir -p "${hermes_orchestrator}/skins"
ln -sfn "${hermes_default}/skins/wallust.yaml" "${hermes_orchestrator}/skins/wallust.yaml"

# --clone snapshots the default profile once, so configure both
for hermes_home in "${hermes_default}" "${hermes_orchestrator}"; do
    export HERMES_HOME="${hermes_home}"

    # one interpreter instead of a hermes launch per key; set_config_value coerces like `hermes config set`
    ORCHESTRATOR="${hermes_orchestrator}" /opt/hermes-agent/venv/bin/python - <<'PY'
import os
from hermes_cli.config import set_config_value
from hermes_cli.skin_cmd import _use
settings = [
    ("display.interface", "tui"),
    # routing: anthropic, then free nous; never the local llm group, it is for chat only
    ("model.default", "claude-sonnet-5"),
    ("model.provider", "anthropic"),
    ("delegation.provider", "nous"),
    ("delegation.model", "meituan/longcat-2.0:free"),
    ("fallback_providers", '[{"provider":"nous","model":"meituan/longcat-2.0:free"},{"provider":"nous","model":"poolside/laguna-s-2.1:free"}]'),
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
