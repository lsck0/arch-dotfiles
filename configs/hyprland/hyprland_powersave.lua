-- power saver (toggle-powermode.sh: forced, or auto on battery): drop every gpu-busy effect
local runtime = os.getenv("XDG_RUNTIME_DIR")
if not runtime then return end

local function toggle_get(name)
    local f = io.open(runtime .. "/toggles/" .. name, "r")
    if not f then return nil end
    local value = f:read("l")
    f:close()
    return value
end

if toggle_get("powersaver") ~= "on" then return end

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
