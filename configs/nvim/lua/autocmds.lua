local autocmd = vim.api.nvim_create_autocmd
local group = vim.api.nvim_create_augroup

autocmd("TextYankPost", {
    desc = "Highlight when yanking text",
    group = group("highlight-yank", { clear = true }),
    callback = function()
        vim.highlight.on_yank()
    end,
})

autocmd("User", {
    pattern = "GitConflictDetected",
    callback = function()
        vim.notify("Conflict detected in " .. vim.fn.expand("<afile>"))
        vim.keymap.set("n", "cww", function()
            engage.conflict_buster()
            create_buffer_local_mappings()
        end)
    end
})
