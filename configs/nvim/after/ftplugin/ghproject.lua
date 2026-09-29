-- window-local display for the ghproject kanban board

vim.wo.number = false
vim.wo.relativenumber = false
vim.wo.signcolumn = "no"
vim.wo.foldcolumn = "0"
vim.wo.colorcolumn = ""
vim.wo.cursorline = false
vim.wo.wrap = false
vim.wo.list = false
vim.wo.winfixwidth = false
vim.wo.winfixheight = false

-- board highlight groups, linked to builtins so any theme (ayu/pywal/...) fits
local function ghproject_hl_apply()
    local function set(name, target)
        vim.api.nvim_set_hl(0, name, { link = target, default = true })
    end
    local sep = vim.fn.hlexists("WinSeparator") == 1 and "WinSeparator" or "Comment"
    set("GhProjectTitle", "Title")
    set("GhProjectHint", "Comment")
    set("GhProjectSep", sep)
    set("GhProjectSel", "Visual")
    set("GhProjectDim", "Comment")
    -- one accent group per column, spread across the theme's syntax palette
    local accents = { "Function", "Constant", "String", "Type", "Keyword", "Special", "Identifier" }
    for i, target in ipairs(accents) do
        set("GhProjectHeader" .. i, target)
    end
end

if not vim.g.ghproject_hl_setup then
    vim.g.ghproject_hl_setup = true
    ghproject_hl_apply()
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("GhProjectHighlights", { clear = true }),
        callback = ghproject_hl_apply,
    })
end
