local WINDOW_OPTIONS = {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    colorcolumn = "",
    cursorline = false,
    wrap = false,
    list = false,
}
local HEADER_ACCENTS = { "Function", "Constant", "String", "Type", "Keyword", "Special", "Identifier" }

-- [0][0] is :setlocal, so other buffers in this window keep theirs
for name, value in pairs(WINDOW_OPTIONS) do
    vim.wo[0][0][name] = value
end

local function ghproject_hl_apply()
    local function set(name, target)
        vim.api.nvim_set_hl(0, name, { link = target, default = true })
    end
    set("GhProjectTitle", "Title")
    set("GhProjectHint", "Comment")
    set("GhProjectSep", "WinSeparator")
    set("GhProjectSel", "Visual")
    set("GhProjectDim", "Comment")
    for i, target in ipairs(HEADER_ACCENTS) do
        set("GhProjectHeader" .. i, target)
    end
end

ghproject_hl_apply()
vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("GhProjectHighlights", { clear = true }),
    callback = ghproject_hl_apply,
})
