local M = {}

local WAL = (vim.env.XDG_CACHE_HOME or (vim.env.HOME .. "/.cache")) .. "/wal/"
local MARKER = WAL .. "nvim_theme"
local STYLE_JSON = (vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. "/.config")) .. "/dotfiles/style.json"

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
-- no marker (or an empty one) means the stock theme; a bad name or a failed apply falls back to FALLBACK
local DEFAULT = "ayu-dark"
local FALLBACK = "wal"

local AYU_LINENR = {
    ["ayu-dark"] = "#636A72",
    ["ayu-light"] = "#8A9199",
    ["ayu-mirage"] = "#6C7A8B",
}

local CLEAR_BG = {
    "Normal",
    "NormalNC",
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
    "StatusLineNC",
    "EndOfBuffer",
    "TabLine",
    "TabLineFill",
    "WinSeparator",
}
local CLEAR_BG_PREFIX = "^Buffer"
-- neovide shows its window through only where a cell takes Normal's bg, so there the bars clear and Normal keeps its own
local NEOVIDE_KEEP = { Normal = true, NormalNC = true }
-- the sidebar tree is a split like the editor: its window takes Normal's bg, which neovide draws as the same glass
local SIDEBAR_NORMAL = { NeoTreeNormal = "Normal", NeoTreeNormalNC = "NormalNC", NeoTreeEndOfBuffer = "EndOfBuffer" }
local CLEAR_FG_BG = { "BufferCurrent", "BufferOffset", "BufferVisible", "StatusLine" }
-- Floats keep the colorscheme's opaque bg (ghostty fills a cell bg opaque), so code over a busy wallpaper stays
-- readable in them. A frame or picker group a colorscheme gives only a fg (ayu's FloatBorder, gruvbox's
-- TelescopeNormal) takes NormalFloat's bg; one it leaves undefined keeps the plugin's own link.
local FLOAT_FILL = { "FloatBorder", "FloatTitle", "FloatFooter", "TelescopeNormal", "TelescopeBorder" }
-- snacks paints a notification with Normal and gives its frame only a fg, and defines those groups at the first
-- notification, so they are set here: the body as NormalFloat, the frame in snacks' level colours on it.
local NOTIFIER_LEVEL_FG = {
    Error = "DiagnosticError",
    Warn = "DiagnosticWarn",
    Info = "DiagnosticInfo",
    Debug = "NonText",
    Trace = "NonText",
}
local NOTIFIER_PARTS = { "Border", "Title", "Footer", "Icon" }

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

-- Links followed by hand: with link = false nvim resolves through the current window's winhighlight, so a start on
-- the snacks dashboard (NormalFloat:SnacksDashboardNormal) read the dashboard's bg for NormalFloat. The bound is
-- nvim's own link depth, against a cycle.
local LINK_DEPTH_MAX = 100
local function hl_get(name)
    local hl = vim.api.nvim_get_hl(0, { name = name })
    for _ = 1, LINK_DEPTH_MAX do
        if not hl.link then
            return hl
        end
        hl = vim.api.nvim_get_hl(0, { name = hl.link })
    end
    return {}
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

-- After every ColorScheme handler. In neovide a cleared Normal bg falls back to near-black, so Normal keeps its bg there
-- and neovide_normal_opacity makes it, and every cell cleared to it, transparent.
local function transparency_apply()
    for _, name in ipairs(CLEAR_BG) do
        if not (vim.g.neovide and NEOVIDE_KEEP[name]) then
            background_clear(hl_get(name), name)
        end
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
    for name, target in pairs(SIDEBAR_NORMAL) do
        vim.api.nvim_set_hl(0, name, { link = target })
    end
    local float_bg = hl_get("NormalFloat").bg
    for _, name in ipairs(FLOAT_FILL) do
        local hl = hl_get(name)
        if next(hl) and not hl.bg then
            hl.bg = float_bg
            vim.api.nvim_set_hl(0, name, hl)
        end
    end
    for level, fg_group in pairs(NOTIFIER_LEVEL_FG) do
        vim.api.nvim_set_hl(0, "SnacksNotifier" .. level, { link = "NormalFloat" })
        local frame = { fg = hl_get(fg_group).fg, bg = float_bg }
        for _, part in ipairs(NOTIFIER_PARTS) do
            vim.api.nvim_set_hl(0, "SnacksNotifier" .. part .. level, frame)
        end
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
    name = name and name ~= "" and name or DEFAULT
    current = name
    local colorscheme = COLORSCHEMES[name] or FALLBACK
    local background = background_from_wal()
    if background and background ~= vim.o.background then
        -- unset first: setting 'background' reloads the outgoing colorscheme
        vim.g.colors_name = nil
        vim.o.background = background
    end
    -- a colorscheme clears only when colors_name is set
    vim.cmd.highlight("clear")
    local ok, err = pcall(vim.cmd.colorscheme, colorscheme)
    if not ok then
        vim.schedule(function()
            vim.notify(
                "theme: failed to apply '" .. name .. "', falling back to " .. FALLBACK .. "\n" .. tostring(err),
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
