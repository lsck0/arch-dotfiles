local platform = require("platform")

-- desktop: 1-4 right (main), 5-10 left; laptop: all on the panel
for workspace = 1, 10 do
    local monitor = platform.laptop and "eDP-1" or (workspace <= 4 and "DP-2" or "DP-1")
    hl.workspace_rule({
        workspace = tostring(workspace),
        monitor = monitor,
    })
end

-- app homes are for the desktop, where 5-10 sit on the left monitor; on a single panel they only yank apps off the
-- workspace they were opened on
if platform.form_factor == "desktop" then
    hl.window_rule({
        match = {
            class = "^steam$",
        },
        workspace = "1",
    })

    for _, class in ipairs({ "^Spotify$", "^discord$" }) do
        hl.window_rule({
            match = {
                class = class,
            },
            workspace = "5",
            no_initial_focus = true,
        })
    end

    hl.window_rule({
        match = {
            class = "^com.obsproject.Studio$",
        },
        workspace = "7",
    })
end

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
