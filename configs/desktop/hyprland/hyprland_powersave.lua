local runtime = os.getenv("XDG_RUNTIME_DIR")
local f = runtime and io.open(runtime .. "/toggles/powersaver", "r")
if not f then
    return
end
local state = f:read("l")
f:close()
if state ~= "on" then
    return
end

hl.config({
    animations = {
        enabled = false,
    },
    decoration = {
        screen_shader = "",
        blur = { enabled = false },
        shadow = { enabled = false },
    },
})

if hl.plugin.dynamic_cursors ~= nil then
    hl.config({ plugin = { dynamic_cursors = { enabled = false } } })
end
