"""Set and remove the hermes settings and set the agent-guard hooks the hermes module passes as JSON (argv[1]) in the
profile at HERMES_HOME, in hermes' own venv: one interpreter instead of a hermes launch per key."""

import json
import sys

from agent.shell_hooks import _record_approval
from hermes_cli.config import load_config, save_config, set_config_value
from hermes_cli.skin_cmd import _use

want = json.loads(sys.argv[1])
for key, value in want["settings"].items():
    # force: a key may be real but missing from this hermes version's schema (e.g. model_aliases)
    set_config_value(key, value if isinstance(value, str) else json.dumps(value), force=True)
_use(want["skin"])

config = load_config()
hooks = config.setdefault("hooks", {})
for event, command in want["hooks"].items():
    others = [h for h in hooks.get(event) or [] if "agent-guard" not in str(h.get("command", ""))]
    hooks[event] = others + [{"command": command}]
    _record_approval(event, command)
for key in want["remove"]:
    *parents, leaf = key.split(".")
    parent = config
    for part in parents:
        parent = parent.get(part) or {}
    parent.pop(leaf, None)
# a merge with the file on disk would bring the removed keys back
save_config(config, merge_existing=not want["remove"])
