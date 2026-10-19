-- [0][0] is :setlocal, so other buffers in this window keep theirs

vim.wo[0][0].number = false
vim.wo[0][0].relativenumber = false
vim.wo[0][0].signcolumn = "no"
vim.wo[0][0].foldcolumn = "0"
vim.wo[0][0].colorcolumn = ""
vim.wo[0][0].cursorline = false
vim.wo[0][0].wrap = false
vim.wo[0][0].list = false

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
