# creating

- MCP servers follow the root `AGENTS.md`; blender-mcp and obs-mcp are AppArmor-confined.
- blender's bridge never auto-starts: `blender-mcp-bridge [file]`.
- `obs`: collections and profiles are rendered per machine and carried back by the `backup` verb; the portal
  RestoreToken is never committed; `basic.ini` keeps `@KEY@` placeholders. Details: `l-dotfiles-streaming`.
- App state that isn't reproducible config goes through a `backup`/`link` pair, never set by hand.
