local platform = require("platform")

-- desktop: 1-4 left, 5-9 right; laptop: all on the panel
local workspace_monitor = platform.laptop
    and { "eDP-1", "eDP-1", "eDP-1", "eDP-1", "eDP-1", "eDP-1", "eDP-1", "eDP-1", "eDP-1" }
    or { "DP-2", "DP-2", "DP-2", "DP-2", "DP-1", "DP-1", "DP-1", "DP-1", "DP-1" }

for workspace, monitor in ipairs(workspace_monitor) do
    hl.workspace_rule({
        workspace = tostring(workspace),
        monitor = monitor,
    })
end

hl.window_rule({
    match = {
        class = "^steam$",
    },
    workspace = "1",
})

hl.window_rule({
    match = {
        class = "^Spotify$",
    },
    workspace = "5",
})

hl.window_rule({
    match = {
        class = "^discord$",
    },
    workspace = "5",
})

hl.window_rule({
    match = {
        class = "^com.obsproject.Studio$",
    },
    workspace = "7",
})

hl.window_rule({
    match = {
        class = "^Spotify$",
    },
    no_initial_focus = true,
})

hl.window_rule({
    match = {
        class = "^discord$",
    },
    no_initial_focus = true,
})

-- it flashes a window, move it offscreen
hl.window_rule({
    match = {
        class = "^multi_export_cli.py$",
    },
    float = true,
    move = "1000000 1000000",
})

hl.config({
    dwindle = {
        force_split = 0,
        permanent_direction_override = false,
        preserve_split = true,
        smart_resizing = true,
        smart_split = false,
    },
})
