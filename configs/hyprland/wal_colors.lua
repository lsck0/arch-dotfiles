local FALLBACK = "rgb(2a2a2a)"

local function read_colors()
    local f = io.open(os.getenv("HOME") .. "/.cache/wal/colors", "r")
    if not f then
        return nil
    end

    local colors, i = {}, 0
    for line in f:lines() do
        local hex = line:match("^#(%x%x%x%x%x%x)")
        if hex then
            colors["color" .. i] = "rgb(" .. hex .. ")"
            i = i + 1
        end
    end
    f:close()

    return i > 0 and colors or nil
end

local M = read_colors() or {}

M.background = M.color0
M.foreground = M.color7

return setmetatable(M, {
    __index = function()
        return FALLBACK
    end,
})
