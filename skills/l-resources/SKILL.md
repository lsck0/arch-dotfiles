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
| configure or extend the machine | through the dotfiles and `dot`, never by hand | `l-dotfiles`, `l-dotfiles-*` |
| the homelab's compute and services | reach the lab's hosts and apps from here | `l-homelab` |
| local model inference | a model on the GPU for cheap or private work, not a paid API; `comfy-gen texture\|3d\|image` for textures, meshes and images (Blender's Generate sidebar) | `l-dotfiles` (`configs/llm/`) |
| a heavy or long job | a low-priority scope that never starves the desktop | `l-persona-programmer`, `fence` |
| look at a GUI program | launch it only to inspect it; ask Luca first | `l-dotfiles-gui-testing` |
| drive an app | the MCP server its module registers, never the app scripted blind | `l-dotfiles-add-module` |

The MCP point is the general rule: when an app exposes an MCP server through its dotfiles module, the agent holds
the same automation surface Luca does, so drive the app through that MCP instead of poking at its files or config.
Every installed tool's server is registered (root `AGENTS.md`); there is no per-task switch.

A capability the machine lacks is never installed by hand: `l-dotfiles`, section "Need from another project".
