local function plugin_config(name, opts)
    if hl.plugin[name] ~= nil then
        hl.config({ plugin = { [name] = opts } })
    end
end

plugin_config("dynamic_cursors", {
    enabled = true,
    mode = "none",

    shake = {
        enabled = true,

        threshold = 4,

        base = 4.0,
        speed = 4.0,
        limit = 0.0, -- no ceiling

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
