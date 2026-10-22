local M = {}

local WAL = vim.env.HOME .. "/.cache/wal/"
local MARKER = WAL .. "nvim_theme"
local STYLE_JSON = vim.env.HOME .. "/.config/dotfiles/style.json"

local COLORSCHEMES = {
    ["ayu-dark"] = "ayu-dark",
    ["ayu-light"] = "ayu-light",
    ["ayu-mirage"] = "ayu-mirage",
    ["catppuccin-frappe"] = "catppuccin-frappe",
    ["catppuccin-latte"] = "catppuccin-latte",
    ["catppuccin-macchiato"] = "catppuccin-macchiato",
    ["catppuccin-mocha"] = "catppuccin-mocha",
    ["dracula"] = "dracula",
    ["gruvbox-dark"] = "gruvbox",
    ["gruvbox-dark-soft"] = "gruvbox",
    ["gruvbox-light"] = "gruvbox",
    ["gruvbox-light-soft"] = "gruvbox",
    ["night-owl"] = "night-owl",
    ["nord"] = "nord",
    ["one-dark"] = "onedark",
    ["pywal"] = "wal",
    ["tokyo-night"] = "tokyonight-night",
    ["tokyo-night-day"] = "tokyonight-day",
    ["tokyo-night-storm"] = "tokyonight-storm",
    ["void"] = "tokyonight-night",
}
local FALLBACK = "wal"

local AYU_LINENR = {
    ["ayu-dark"] = "#636A72",
    ["ayu-light"] = "#8A9199",
    ["ayu-mirage"] = "#6C7A8B",
}

local CLEAR_BG = {
    "Normal",
    "NormalNC",
    "NormalFloat",
    "Comment",
    "Constant",
    "Special",
    "Identifier",
    "Statement",
    "PreProc",
    "Type",
    "Underlined",
    "Todo",
    "String",
    "Function",
    "Conditional",
    "Repeat",
    "Operator",
    "Structure",
    "LineNr",
    "NonText",
    "SignColumn",
    "CursorLine",
    "CursorLineNr",
    "StatusLine",
    "StatusLineNC",
    "EndOfBuffer",
    "TelescopeNormal",
    "TabLine",
    "TabLineFill",
    "WinSeparator",
}
local CLEAR_BG_PREFIX = "^Buffer"
local CLEAR_FG_BG = { "BufferCurrent", "BufferOffset", "BufferVisible", "StatusLine" }

local function luminance(rgb)
    local function channel(shift)
        local c = bit.band(bit.rshift(rgb, shift), 0xff) / 255
        return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
end

local function contrast(a, b)
    local la, lb = luminance(a), luminance(b)
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

local function json_read(path)
    local fd = io.open(path, "r")
    if not fd then
        return nil
    end
    local ok, value = pcall(vim.json.decode, fd:read("*a"))
    fd:close()
    return ok and value or nil
end

local style = json_read(STYLE_JSON) or {}

local function hl_get(name)
    return vim.api.nvim_get_hl(0, { name = name, link = false })
end

local function background_from_wal()
    local colors = json_read(WAL .. "colors.json")
    local hex = colors and colors.special and colors.special.background
    local rgb = hex and tonumber(hex:match("^#(%x%x%x%x%x%x)$") or "", 16)
    if not rgb or not style.light_luminance then
        return nil
    end
    return luminance(rgb) >= style.light_luminance and "light" or "dark"
end

local function selection_apply()
    local accent = hl_get("Function").fg or hl_get("Title").fg
    local normal = hl_get("Normal")
    if not accent or not normal.fg then
        return
    end
    local text = normal.fg
    if normal.bg and contrast(accent, normal.bg) > contrast(accent, normal.fg) then
        text = normal.bg
    end
    if style.text_ratio and contrast(accent, text) < style.text_ratio then
        text = luminance(accent) >= style.white_text_luminance_max and 0x000000 or 0xffffff
    end
    vim.api.nvim_set_hl(0, "PmenuSel", { fg = text, bg = accent, bold = true })
    vim.api.nvim_set_hl(0, "BlinkCmpMenuSelection", { link = "PmenuSel" })
end

local function separator_apply()
    local dim = hl_get("NonText").fg or hl_get("WinSeparator").fg
    vim.api.nvim_set_hl(0, "WinSeparator", { fg = dim, ctermfg = 8 })
end

local function background_clear(hl, name)
    if hl.link or not (hl.bg or hl.ctermbg) then
        return
    end
    hl.bg, hl.ctermbg = nil, nil
    vim.api.nvim_set_hl(0, name, hl)
end

-- Runs after every ColorScheme handler: plugins (barbar, lualine) redefine their groups in theirs.
local function transparency_apply()
    for _, name in ipairs(CLEAR_BG) do
        background_clear(hl_get(name), name)
    end
    for name, hl in pairs(vim.api.nvim_get_hl(0, {})) do
        if name:find(CLEAR_BG_PREFIX) then
            background_clear(hl, name)
        end
    end
    for _, name in ipairs(CLEAR_FG_BG) do
        local hl = hl_get(name)
        hl.fg, hl.bg, hl.ctermfg, hl.ctermbg = nil, nil, nil, nil
        vim.api.nvim_set_hl(0, name, hl)
    end
end

local current = nil

local function overrides_apply()
    local linenr = AYU_LINENR[current]
    if linenr then
        vim.api.nvim_set_hl(0, "LineNr", { fg = linenr })
    end
    selection_apply()
    separator_apply()
    vim.schedule(transparency_apply)
end

local group = vim.api.nvim_create_augroup("theme-overrides", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = overrides_apply })
-- barbar and lualine load after the first colorscheme
vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "VeryLazy",
    once = true,
    callback = function()
        vim.schedule(transparency_apply)
    end,
})

function M.apply(name)
    name = name and name ~= "" and name or "ayu-dark"
    current = name
    local colorscheme = COLORSCHEMES[name] or FALLBACK
    local background = background_from_wal()
    if background and background ~= vim.o.background then
        -- unset first: setting 'background' reloads the outgoing colorscheme
        vim.g.colors_name = nil
        vim.o.background = background
    end
    local ok, err = pcall(vim.cmd.colorscheme, colorscheme)
    if not ok then
        vim.schedule(function()
            vim.notify(
                "theme: failed to apply '" .. name .. "', falling back to wal\n" .. tostring(err),
                vim.log.levels.WARN
            )
        end)
        pcall(vim.cmd.colorscheme, FALLBACK)
    end
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
