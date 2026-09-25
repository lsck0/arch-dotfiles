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

-- auto-create parent dirs on save (replaces mkdir.nvim)
autocmd("BufWritePre", {
    desc = "Create missing parent directories on save",
    group = group("mkdir-on-save", { clear = true }),
    callback = function(args)
        if args.match:match("^%w+://") then return end -- skip URLs (oil://, scp://, ...)
        vim.fn.mkdir(vim.fn.fnamemodify(args.file, ":p:h"), "p")
    end,
})

-- reload files changed on disk (replaces neovim-auto-autoread)
vim.o.autoread = true
autocmd({ "FocusGained", "TermClose", "TermLeave", "CursorHold" }, {
    desc = "Reload files changed outside nvim",
    group = group("auto-read", { clear = true }),
    callback = function()
        if vim.fn.getcmdwintype() == "" then vim.cmd.checktime() end
    end,
})

-- relativenumber in normal, absolute in insert/unfocused (replaces nvim-numbertoggle)
autocmd({ "BufEnter", "FocusGained", "InsertLeave", "WinEnter" }, {
    desc = "Relative line numbers when active",
    group = group("numbertoggle", { clear = true }),
    callback = function()
        if vim.wo.number and vim.fn.mode() ~= "i" then vim.wo.relativenumber = true end
    end,
})
autocmd({ "BufLeave", "FocusLost", "InsertEnter", "WinLeave" }, {
    desc = "Absolute line numbers when inactive",
    group = group("numbertoggle-off", { clear = true }),
    callback = function()
        if vim.wo.number then vim.wo.relativenumber = false end
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

-- spell check for prose filetypes
autocmd("FileType", {
    desc = "Enable spell check for prose",
    group = group("prose-spell", { clear = true }),
    pattern = { "markdown", "gitcommit", "text", "tex", "plaintex", "org" },
    callback = function()
        vim.opt_local.spell = true
        vim.opt_local.spelllang = "en"
    end,
})

-- open the snacks.explorer sidebar on startup, cursor stays in the main buffer.
autocmd("VimEnter", {
    desc = "Auto-open file explorer sidebar",
    group = group("auto-explorer", { clear = true }),
    callback = function()
        if vim.g.started_by_firenvim then return end
        if vim.fn.argc() > 1 then return end            -- diff/multi-file: leave alone
        local ft = vim.bo.filetype
        if ft == "gitcommit" or ft == "gitrebase" then return end
        if vim.bo.buftype ~= "" then return end          -- stdin, help, etc.
        -- belt-and-suspenders: never stack a second tree if one is already open
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            local ft = vim.api.nvim_get_option_value("filetype", { buf = vim.api.nvim_win_get_buf(w) })
            if ft == "neo-tree" or ft == "snacks_picker_list" then return end
        end
        local main = vim.api.nvim_get_current_win()
        -- chdir to the git root and open with NO explicit cwd, so the autocmd,
        -- replace_netrw and follow_file all resolve the same cwd string. Passing
        -- differing cwd forms made snacks stack a duplicate root per opener.
        local root = require("lib.root").git()
        if root and root ~= "" then pcall(vim.cmd.tcd, vim.fn.fnameescape(root)) end
        require("snacks").explorer()
        -- the picker grabs focus asynchronously after it opens, so restore focus
        vim.defer_fn(function()
            if vim.api.nvim_win_is_valid(main) then
                vim.api.nvim_set_current_win(main)
            end
        end, 100)
    end,
})

-- flag jupytext notebook buffers so the pyright handler can drop IPython-builtin noise.
autocmd("FileType", {
    desc = "Detect jupytext notebook buffers",
    group = group("jupytext-detect", { clear = true }),
    pattern = "python",
    callback = function(args)
        local head = vim.api.nvim_buf_get_lines(args.buf, 0, 12, false)
        for _, line in ipairs(head) do
            if line:match("^#%s*jupytext:") or line:match("format_name:%s*percent") then
                vim.b[args.buf].is_jupytext = true
                return
            end
        end
    end,
})
