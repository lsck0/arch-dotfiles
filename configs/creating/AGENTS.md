# creating

Extends the root `AGENTS.md`. Content-creation apps, most paired with an agent MCP server (gimp and krita have none).

## Modules

- `audacity`: the audio editor plus audacity-mcp-server (stdio over audacity's mod-script-pipe fifos).
- `blender`: Blender plus Blender Lab's blender-mcp (stdio, relaying into a running blender over a loopback bridge).
  The bridge never auto-starts: `blender-mcp-bridge [file]` (or the launcher action "Blender with MCP bridge") opens it.
- `gimp`: GIMP with the PhotoGIMP config (photoshop layout and shortcuts).
- `inkscape`: Inkscape plus inkscape_mcp (headless cli, live over d-bus when an instance is open).
- `krita`: the paint app (first start builds its resource db over the full font set).
- `obs`: OBS; collections and profiles rendered for this machine (canvas, monitoring device, mic, webcam, encoders,
  vaapi node: options detected from the hardware), carried back into the repo by the module's `backup` verb (the portal
  RestoreToken is per machine, never committed; the profiles' `basic.ini` keep `@KEY@` placeholders).
- `openscad`: OpenSCAD plus openscad-mcp (stdio over the openscad cli).
- `apps`: the creative apps with no config of their own, packages plus their first-run dialogs answered (kdenlive,
  famistudio, rawtherapee, lmms).

## Conventions

- An app with an MCP server wires it in its `mod.nu` via `json-merge` on `~/.claude.json`, present only when the
  app is installed, and pinned where it is third-party (checkout/release/content hash), never upstream head.
- The MCPs are local: stdio over the app's own scripting pipe or a loopback bridge, no public port. The blender-mcp
  relay and obs-mcp are AppArmor-confined (`base/apparmor profiles/{blender-mcp,obs-mcp}`); the blender add-on's
  in-process rce is not confined.
- App state that is not reproducible config is saved by the module's `backup` verb into `configs/secrets/` or the module
  and restored by its `link`, not left to the user to set by hand.
