local function plugin_config(name, opts, aliases)
    for _, alias in ipairs(aliases or { name }) do
        if hl.plugin[alias] ~= nil then
            hl.config({ plugin = { [name] = opts } })
            return true
        end
    end

    return false
end

plugin_config("dynamic_cursors", {
    enabled = true,
    mode = "none",

    shake = {
        effects = true,
        threshold = 4,
        timeout = 500,
    },

    hyprcursor = {
        enabled = true,
        nearest = true,
        resolution = -1,
        fallback = "clientside",
    },
})

plugin_config("overview", {
    showEmptyWorkspace = 0,
    showNewWorkspace = 0,
    centerAligned = 1,
    exitOnClick = 1,
    exitOnSwitch = 1,
    panelHeight = 250,
    affectStrut = 0,
    panelColor = "rgba(00000066)",
    workspaceActiveBackground = "rgba(00000066)",
    workspaceInactiveBackground = "rgba(00000099)",
}, { "overview", "Hyprspace" })

plugin_config("hyprscrolling", {
    column_width = 0.8,
    fullscreen_on_one_column = true,
})
