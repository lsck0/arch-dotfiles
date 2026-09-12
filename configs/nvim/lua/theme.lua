-- Theme dispatch.
local M = {}

local MARKER = vim.env.HOME .. "/.cache/wal/nvim_theme"

M.current = "pywal"

function M.apply(name)
    name = name and name ~= "" and name or "pywal"
    local ok, err = pcall(function() require("themes." .. name).apply() end)
    if ok then
        M.current = name
        return
    end
    vim.schedule(function()
        vim.notify(
            "theme: failed to apply '" .. name .. "', falling back to pywal\n" .. tostring(err),
            vim.log.levels.WARN
        )
    end)
    M.current = "pywal"
    pcall(function() require("themes.pywal").apply() end)
end

function M.apply_from_marker()
    local f = io.open(MARKER, "r")
    if not f then
        M.apply(nil)
        return
    end
    local name = f:read("*l")
    f:close()
    M.apply(name and name:gsub("%s+$", "") or nil)
end

return M
