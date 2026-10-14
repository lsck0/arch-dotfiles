local platform = require("platform")

for workspace, monitor in pairs(platform.workspaces) do
    hl.workspace_rule({
        workspace = workspace,
        monitor = monitor,
    })
end

for _, home in ipairs(platform.app_workspaces) do
    hl.window_rule({
        match = {
            class = home.class,
        },
        workspace = tostring(home.workspace),
        no_initial_focus = home.silent or nil,
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
