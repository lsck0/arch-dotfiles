-- toggle-powermode.sh power-saver: drop every effect that keeps the gpu awake
local runtime = os.getenv("XDG_RUNTIME_DIR")
if not runtime then return end

local f = io.open(runtime .. "/toggles/powermode", "r")
if not f then return end
local mode = f:read("l")
f:close()
if mode ~= "power-saver" then return end

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
