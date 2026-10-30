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
        workspace = tostring(home.workspace) .. (home.silent and " silent" or ""),
        no_initial_focus = home.silent or nil,
    })
end

-- themix's headless export still maps a window for a moment
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
