local autocmd = vim.api.nvim_create_autocmd
local group = vim.api.nvim_create_augroup

autocmd("TextYankPost", {
    desc = "Highlight when yanking text",
    group = group("highlight-yank", { clear = true }),
    callback = function()
        vim.highlight.on_yank()
    end,
})

autocmd("BufReadPost", {
    desc = "Restore cursor to last position when reopening a file",
    group = group("restore-cursor", { clear = true }),
    callback = function(args)
        local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
        local lcount = vim.api.nvim_buf_line_count(args.buf)
        if mark[1] > 0 and mark[1] <= lcount then
            pcall(vim.api.nvim_win_set_cursor, 0, mark)
        end
    end,
})

autocmd("FileType", {
    desc = "Start treesitter highlighting + indent",
    group = group("treesitter-start", { clear = true }),
    callback = function(args)
        local buf = args.buf
        local ft = vim.bo[buf].filetype
        local lang = vim.treesitter.language.get_lang(ft) or ft
        if pcall(vim.treesitter.start, buf, lang) then
            vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
    end,
})
