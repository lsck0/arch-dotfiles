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

    -- Shake to find: magnify the cursor while it is being shaken.
    shake = {
        enabled = true,

        -- lower than the default 6.0, so a short flick already triggers
        threshold = 4,

        base = 4.0,  -- magnification the moment a shake is detected
        speed = 4.0, -- extra magnification per second of continued shaking
        limit = 0.0, -- no ceiling

        -- how long it stays magnified after the shake stops
        timeout = 500,

        -- mode is "none", so there is no tilt/rotate to show while shaking; kept explicit so switching mode later does not silently change this.
        effects = true,
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
