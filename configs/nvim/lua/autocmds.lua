local autocmd = vim.api.nvim_create_autocmd
local group = vim.api.nvim_create_augroup

autocmd("TextYankPost", {
    desc = "Highlight when yanking text",
    group = group("highlight-yank", { clear = true }),
    callback = function()
        vim.highlight.on_yank()
    end,
})
