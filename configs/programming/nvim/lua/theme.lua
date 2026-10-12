local M = {}

local MARKER = vim.env.HOME .. "/.cache/wal/nvim_theme"

-- theme name -> colorscheme; lazy.nvim loads the owning plugin on ColorSchemePre.
-- a name with no nvim port falls through to the pywal palette.
local COLORSCHEMES = {
    ["ayu-dark"] = "ayu-dark",
    ["ayu-light"] = "ayu-light",
    ["ayu-mirage"] = "ayu-mirage",
    ["catppuccin-macchiato"] = "catppuccin-macchiato",
    ["catppuccin-mocha"] = "catppuccin-mocha",
    ["dracula"] = "dracula",
    ["gruvbox-dark"] = "gruvbox",
    ["night-owl"] = "night-owl",
    ["nord"] = "nord",
    ["one-dark"] = "onedark",
    ["pywal"] = "pywal",
    ["tokyo-night"] = "tokyonight-night",
    ["void"] = "tokyonight-night", -- tokyonight-night derivative
}

-- upstream ayu LineNr is ~1.2:1 against bg, nearly invisible
local AYU_LINENR = {
    ["ayu-dark"] = "#636A72",
    ["ayu-light"] = "#8A9199",
    ["ayu-mirage"] = "#6C7A8B",
}

function M.apply(name)
    name = name and name ~= "" and name or "ayu-dark"
    local colorscheme = COLORSCHEMES[name] or "pywal"
    local ok, err = pcall(vim.cmd.colorscheme, colorscheme)
    if not ok then
        vim.schedule(function()
            vim.notify(
                "theme: failed to apply '" .. name .. "', falling back to pywal\n" .. tostring(err),
                vim.log.levels.WARN
            )
        end)
        pcall(vim.cmd.colorscheme, "pywal")
        return
    end
    local linenr = AYU_LINENR[name]
    if linenr then vim.api.nvim_set_hl(0, "LineNr", { fg = linenr }) end
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
