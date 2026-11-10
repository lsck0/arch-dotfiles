"""Set and remove the hermes settings, set the agent-guard hooks and the dotfiles' MCP servers (null drops one) the hermes
module passes as JSON (argv[1]) in the profile at HERMES_HOME, in hermes' own venv: one interpreter instead of a hermes
launch per key."""

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
# every event loses its guard hooks first, so a guard that is gone (idle-guards off) leaves none behind
for event in list(hooks):
    others = [h for h in hooks.get(event) or [] if "agent-guard" not in str(h.get("command", ""))]
    if others:
        hooks[event] = others
    else:
        hooks.pop(event)
for event, command in want["hooks"].items():
    hooks[event] = hooks.get(event, []) + [{"command": command}]
    _record_approval(event, command)
if not hooks:
    config.pop("hooks")
servers = config.get("mcp_servers") or {}
# save_config keeps keys of an entry that is still on disk, so a spec that changed shape (an http server now behind
# mcp-gate's stdio) would keep its old url beside the new command, and hermes picks the url: such entries go first
changed = [name for name, spec in want["mcp"].items() if spec is not None and name in servers and servers[name] != spec]
if changed:
    for name in changed:
        servers.pop(name)
    save_config(config)
    config = load_config()
    hooks = config.setdefault("hooks", {})
    servers = config.get("mcp_servers") or {}
dropped = [name for name, spec in want["mcp"].items() if spec is None and servers.pop(name, None) is not None]
servers.update({name: spec for name, spec in want["mcp"].items() if spec is not None})
if servers:
    config["mcp_servers"] = servers
else:
    config.pop("mcp_servers", None)
for key in want["remove"]:
    *parents, leaf = key.split(".")
    parent = config
    for part in parents:
        parent = parent.get(part) or {}
    parent.pop(leaf, None)
# a merge with the file on disk would bring the removed keys back
save_config(config, merge_existing=not want["remove"] and not dropped)
