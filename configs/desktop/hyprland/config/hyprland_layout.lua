local platform = require("platform")

for workspace, monitor in pairs(platform.workspaces) do
    hl.workspace_rule({ workspace = workspace, monitor = monitor })
end

-- the tag the tabbed homes of one workspace share
local function tabs_tag(workspace)
    return "tabs-" .. tostring(workspace)
end

for _, home in ipairs(platform.app_workspaces) do
    hl.window_rule({
        match = { class = home.class },
        workspace = tostring(home.workspace) .. (home.silent and " silent" or ""),
        no_initial_focus = home.silent or nil,
        tag = home.tabbed and ("+" .. tabs_tag(home.workspace)) or nil,
    })
end

local function tabs_tag_of(window)
    for _, tag in ipairs(window.tags or {}) do
        -- a tag a rule set carries a trailing *
        local name = tag:gsub("%*$", "")
        if name:match("^tabs%-") then
            return name
        end
    end
    return nil
end

-- the direction from one window's centre toward another's, along the axis they lie further apart on
local function direction_toward(from, to)
    local dx = (to.at.x + to.size.x / 2) - (from.at.x + from.size.x / 2)
    local dy = (to.at.y + to.size.y / 2) - (from.at.y + from.size.y / 2)
    if math.abs(dx) >= math.abs(dy) then
        return dx < 0 and "l" or "r"
    end
    return dy < 0 and "u" or "d"
end

-- a tabbed home's window joins the tab group of the first window of its workspace's other tabbed homes, or starts
-- one with it. Rules cannot: group invade only reaches the group under focus, and a silent home opens unfocused. The
-- move needs the workspace shown and focuses the window, so every monitor's workspace and then the focus go back.
hl.on("window.open", function(window)
    local tag = tabs_tag_of(window)
    if not tag then
        return
    end
    for _, other in ipairs(hl.get_windows()) do
        if
            other.address ~= window.address
            and other.workspace.id == window.workspace.id
            and tabs_tag_of(other) == tag
        then
            local active, workspace = hl.get_active_window(), hl.get_active_workspace()
            local shown = {}
            for _, monitor in ipairs(hl.get_monitors()) do
                table.insert(shown, monitor.active_workspace.id)
            end
            hl.dispatch(hl.dsp.focus({ workspace = window.workspace.id }))
            hl.dispatch(hl.dsp.window.move({
                into_or_create_group = direction_toward(window, other),
                window = "address:" .. window.address,
            }))
            for _, id in ipairs(shown) do
                hl.dispatch(hl.dsp.focus({ workspace = id }))
            end
            if active and active.address ~= window.address then
                hl.dispatch(hl.dsp.focus({ window = "address:" .. active.address }))
            elseif workspace then
                hl.dispatch(hl.dsp.focus({ workspace = workspace.id }))
            end
            return
        end
    end
end)

hl.config({
    dwindle = { preserve_split = true },
})
