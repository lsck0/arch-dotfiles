local M = {}

local MARKER = vim.env.HOME .. "/.cache/wal/nvim_theme"

function M.apply(name)
    name = name and name ~= "" and name or "ayu-dark"
    -- themes without a nvim port use the pywal palette
    if #vim.api.nvim_get_runtime_file("lua/themes/" .. name .. ".lua", false) == 0 then name = "pywal" end
    local ok, err = pcall(function() require("themes." .. name).apply() end)
    if ok then return end
    vim.schedule(function()
        vim.notify(
            "theme: failed to apply '" .. name .. "', falling back to pywal\n" .. tostring(err),
            vim.log.levels.WARN
        )
    end)
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
