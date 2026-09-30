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

    -- shake to find
    shake = {
        enabled = true,

        -- default 6.0; lower so a short flick triggers
        threshold = 4,

        base = 4.0,
        speed = 4.0, -- per second of shaking
        limit = 0.0, -- no ceiling

        -- ms magnified after the shake stops
        timeout = 500,

        -- no-op while mode is "none", explicit for a later mode switch
        effects = true,
    },

    hyprcursor = {
        enabled = true,
        nearest = true,
        resolution = -1,
        fallback = "clientside",
    },
})
