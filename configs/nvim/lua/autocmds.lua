local autocmd = vim.api.nvim_create_autocmd
local group = vim.api.nvim_create_augroup

autocmd("TextYankPost", {
    desc = "Highlight when yanking text",
    group = group("highlight-yank", { clear = true }),
    callback = function()
        vim.hl.on_yank()
    end,
})

autocmd("FileType", {
    desc = "Hard-wrap prose at textwidth",
    group = group("prose-hardwrap", { clear = true }),
    pattern = { "markdown", "text", "gitcommit", "tex", "plaintex", "rst", "org", "typst" },
    callback = function()
        vim.opt_local.textwidth = 100
        vim.opt_local.formatoptions:append("t")
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

autocmd("BufWritePre", {
    desc = "Create missing parent directories on save",
    group = group("mkdir-on-save", { clear = true }),
    callback = function(args)
        if args.match:match("^%w+://") then return end -- skip URLs (oil://, scp://, ...)
        vim.fn.mkdir(vim.fn.fnamemodify(args.file, ":p:h"), "p")
    end,
})

vim.o.autoread = true
autocmd({ "FocusGained", "TermClose", "TermLeave" }, {
    desc = "Reload files changed outside nvim",
    group = group("auto-read", { clear = true }),
    callback = function()
        if vim.fn.getcmdwintype() == "" then vim.cmd.checktime() end
    end,
})

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
        -- tex keeps vim syntax: vimtex mathzone detection needs it
        if ft == "tex" or ft == "plaintex" or ft == "bib" then return end
        local lang = vim.treesitter.language.get_lang(ft) or ft
        if pcall(vim.treesitter.start, buf, lang) then
            vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
    end,
})

autocmd("FileType", {
    desc = "Enable spell check for prose",
    group = group("prose-spell", { clear = true }),
    pattern = { "markdown", "gitcommit", "text", "tex", "plaintex", "org" },
    callback = function()
        vim.opt_local.spell = true
        vim.opt_local.spelllang = "en"
    end,
})

-- before auto-explorer: it skips the netrw listing because that is not a normal buffer
autocmd("VimEnter", {
    desc = "Directory argument: cd into it and start on an empty buffer, not netrw",
    group = group("dir-arg", { clear = true }),
    callback = function()
        if vim.fn.argc() ~= 1 or vim.fn.isdirectory(vim.fn.argv(0)) == 0 then return end
        vim.cmd.cd(vim.fn.fnameescape(vim.fn.fnamemodify(vim.fn.argv(0), ":p")))
        vim.cmd("%argdelete")
        vim.cmd.enew()
        local empty = vim.api.nvim_get_current_buf()
        -- both the directory buffer and the netrw listing netrw swapped in for it
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            local listing = vim.bo[buf].filetype == "netrw" or vim.fn.isdirectory(vim.api.nvim_buf_get_name(buf)) == 1
            if buf ~= empty and listing then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end
    end,
})

autocmd("VimEnter", {
    desc = "Auto-open file explorer sidebar",
    group = group("auto-explorer", { clear = true }),
    callback = function()
        if vim.g.started_by_firenvim then return end
        -- only for herdr-open.sh launches
        if vim.env.NVIM_TMS ~= "1" then return end
        if vim.fn.argc() > 1 then return end            -- diff/multi-file: leave alone
        local ft = vim.bo.filetype
        if ft == "gitcommit" or ft == "gitrebase" then return end
        if vim.bo.buftype ~= "" then return end          -- stdin, help, etc.
        -- never stack a second tree
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            local win_ft = vim.api.nvim_get_option_value("filetype", { buf = vim.api.nvim_win_get_buf(w) })
            if win_ft == "snacks_picker_list" then return end
        end
        local main = vim.api.nvim_get_current_win()
        require("lib.explorer").open()
        -- the picker grabs focus async, take it back
        vim.defer_fn(function()
            if vim.api.nvim_win_is_valid(main) then
                vim.api.nvim_set_current_win(main)
            end
        end, 100)
    end,
})

autocmd({ "BufWinEnter", "WinEnter" }, {
    desc = "Reveal the current file in the explorer sidebar",
    group = group("explorer-follow", { clear = true }),
    callback = function()
        -- scheduled: on BufWinEnter the window still reports the outgoing buffer
        vim.schedule(function()
            pcall(function() require("lib.explorer").reveal_current() end)
        end)
    end,
})

-- read by the pyright handler in plugins/lsp.lua
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

-- undofile and shada would persist secret plaintext
autocmd({ "BufReadPre", "BufNewFile" }, {
    desc = "No undo/shada history for secret files",
    group = group("no-secret-history", { clear = true }),
    pattern = { "*/secrets/*", "*.sops.*", "*.env", "*.env.*", ".envrc", "*.gpg", "*.age", "*.asc" },
    callback = function()
        vim.opt_local.undofile = false
        vim.opt_local.swapfile = false
        vim.opt.shada = ""
    end,
})

-- no capitalization spell errors, reapplied after every theme switch
autocmd({ "ColorScheme", "VimEnter" }, {
    desc = "Clear SpellCap highlight",
    group = group("no-spellcap", { clear = true }),
    callback = function()
        vim.api.nvim_set_hl(0, "SpellCap", {})
    end,
})
