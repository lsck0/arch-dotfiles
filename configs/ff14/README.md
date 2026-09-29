# FF14 UI theme (Dalamud)

Cyberpunk cyan theme for XIVLauncher/Dalamud, matching the desktop palette
(accent #39BAE6, ground #0B0E14). It styles Dalamud/plugin windows (the ImGui
UI layer). The game's own HUD is separate: arrange it in-game with `/hudlayout`.

Config lives at `~/.xlcore/dalamudConfig.json` (XIVLauncher.Core on Proton).

## Apply

Dalamud > Settings (`/xlsettings`) > Look & Feel > Style Editor:
1. Add a new style, name it `cyberpunk`.
2. Set the colors from `palette.md` (Colors tab), and the sizing below.
3. Set it as the active style.

Sizing (Variables tab), for the terminal/HUD look:
- WindowRounding 2, ChildRounding 2, FrameRounding 2, PopupRounding 2
- GrabRounding 2, TabRounding 2, ScrollbarRounding 2
- WindowBorderSize 1, FrameBorderSize 1
- WindowPadding 8,8  FramePadding 6,3  ItemSpacing 6,4

`cyberpunk-dalamud.json` is the same values as a reference/backup.
