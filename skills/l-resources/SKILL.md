---
name: l-resources
description: "An orientation skill: what powers an agent has on this machine and which skill drives each. Load when deciding whether a capability exists before working around its absence."
---

# l-resources

An agent running on this machine is a first-class operator, not a guest. It may use the system, the installed
software and the hardware the way Luca does himself: the same tools, the same services, the same credentials in
their stores. So before scripting around a missing capability or declaring something impossible, check here
whether the power already exists and which skill drives it. The default is to reach for the native facility, not
to reinvent it.

First-class means deciding, too, not just tool access. The agent acts with Luca's authority and decides in his
name, stopping only at a genuine fork: a consequential, hard-to-reverse choice that is really his to make. It does
not interrupt him for trivia it can settle from the code, the conventions or a sensible default. The orchestration
and autonomous-mode gates (`l-persona-orchestrator`, `l-spec-driven-development`) are the specialization of this
for a multi-step run.

## Powers and the skill that drives each

| power | how | skill |
|---|---|---|
| configure or extend the machine | through the dotfiles and `dot`, never by hand | `l-dotfiles` and its `l-dotfiles-*` topic skills |
| the homelab's compute and services | reach the lab's hosts and apps from here | `l-homelab` |
| local model inference | run a model on the GPU for cheap or private work, instead of a paid API | `l-dotfiles` (the inference server is a dotfiles module) |
| a heavy or long job | run it in a low-priority scope so it never starves the desktop or a game | `l-persona-programmer` (the `fence` wrapper) |
| look at a GUI program | launch it only to inspect it, on the agent's own headless output | `l-dotfiles-gui-testing` |
| drive an app | use the MCP server its module registers, rather than scripting the app blind | `l-dotfiles` (registers the MCP servers) |

The MCP point is the general rule: when an app exposes an MCP server through its dotfiles module, the agent holds
the same automation surface Luca does, so drive the app through that MCP instead of poking at its files or config.
A connected MCP server spends context on every task whether used or not, so keep the enabled surface task-scoped:
turn on the servers a task needs, not all of them (the enable path is the server's dotfiles module, `l-dotfiles`).

## When another project needs something on the machine

Do not install it. Loading `l-dotfiles` from inside the dotfiles repo, or messaging the dotfiles session from any
other project (list agents, the one named `arch-dotfiles-*`), is the one path for a new package, tool, service,
PATH entry or system setting. Ask with the exact need and continue once it confirms. The machine stays
reproducible from the repo; nothing is changed by hand.
