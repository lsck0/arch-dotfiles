# creating

- blender-mcp and obs-mcp are AppArmor-confined.
- blender's bridge never auto-starts: `blender-mcp-bridge [file]`. The `comfy_generate` extension (the Generate
  sidebar over `llm/comfyui`'s `comfy-gen`) is built and enabled by the `generate-install` step whenever its files
  change.
- `obs`: collections and profiles are rendered per machine and carried back by the `backup` verb; the portal
  RestoreToken is never committed; `basic.ini` keeps `@KEY@` placeholders. The Streaming collection is in secrets'
  `keys/` (its widget urls carry tokens), the stream art (overlays, PNGtuber, badges, `.kra` sources) in
  `state/obs/`: nothing personal in the public tree. Details: `l-dotfiles-streaming`.
- App state that isn't reproducible config goes through a `backup`/`link` pair, never set by hand.
