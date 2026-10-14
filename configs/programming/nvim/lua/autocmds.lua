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
    desc = "Prose: hard-wrap at textwidth, spell-check the natural-language filetypes",
    group = group("prose", { clear = true }),
    pattern = { "markdown", "text", "gitcommit", "tex", "plaintex", "rst", "org", "typst" },
    callback = function(args)
        vim.opt_local.textwidth = 100
        vim.opt_local.formatoptions:append("t")
        local spell = { markdown = true, gitcommit = true, text = true, tex = true, plaintex = true, org = true }
        if spell[vim.bo[args.buf].filetype] then
            vim.opt_local.spell = true
            vim.opt_local.spelllang = "en"
        end
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
        if args.match:match("^%w+://") then
            return
        end
        vim.fn.mkdir(vim.fn.fnamemodify(args.file, ":p:h"), "p")
    end,
})

autocmd({ "FocusGained", "TermClose", "TermLeave" }, {
    desc = "Reload files changed outside nvim",
    group = group("auto-read", { clear = true }),
    callback = function()
        if vim.fn.getcmdwintype() == "" then
            vim.cmd.checktime()
        end
    end,
})

local numbertoggle_active = { BufEnter = true, FocusGained = true, InsertLeave = true, WinEnter = true }
autocmd({ "BufEnter", "FocusGained", "InsertLeave", "WinEnter", "BufLeave", "FocusLost", "InsertEnter", "WinLeave" }, {
    desc = "Relative line numbers when active, absolute when inactive",
    group = group("numbertoggle", { clear = true }),
    callback = function(args)
        if not vim.wo.number then
            return
        end
        if numbertoggle_active[args.event] then
            if vim.fn.mode() ~= "i" then
                vim.wo.relativenumber = true
            end
        else
            vim.wo.relativenumber = false
        end
    end,
})

autocmd("FileType", {
    desc = "Start treesitter highlighting + indent",
    group = group("treesitter-start", { clear = true }),
    callback = function(args)
        local buf = args.buf
        local ft = vim.bo[buf].filetype
        -- tex keeps vim syntax: vimtex mathzone detection needs it
        if ft == "tex" or ft == "plaintex" or ft == "bib" then
            return
        end
        local lang = vim.treesitter.language.get_lang(ft) or ft
        if not pcall(vim.treesitter.start, buf, lang) then
            return
        end
        -- keep the runtime indent script (make's recipe tabs)
        if vim.treesitter.query.get(lang, "indents") then
            vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
    end,
})

-- keep focus on the main window: the picker grabs it async
local function open_explorer_keep_focus()
    local main = vim.api.nvim_get_current_win()
    require("lib.explorer").open()
    vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(main) then
            vim.api.nvim_set_current_win(main)
        end
    end, 100)
end

autocmd("VimEnter", {
    desc = "Open explorer on a directory argument or a herdr launch",
    group = group("auto-explorer", { clear = true }),
    callback = function()
        if vim.fn.argc() == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1 then
            vim.cmd.cd(vim.fn.fnameescape(vim.fn.fnamemodify(vim.fn.argv(0), ":p")))
            vim.cmd("%argdelete")
            vim.cmd.enew()
            local empty = vim.api.nvim_get_current_buf()
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                local listing = vim.bo[buf].filetype == "netrw"
                    or vim.fn.isdirectory(vim.api.nvim_buf_get_name(buf)) == 1
                if buf ~= empty and listing then
                    vim.api.nvim_buf_delete(buf, { force = true })
                end
            end
            open_explorer_keep_focus()
            return
        end
        if vim.g.started_by_firenvim then
            return
        end
        if vim.env.NVIM_TMS ~= "1" then
            return
        end
        if vim.fn.argc() > 1 then
            return
        end
        local ft = vim.bo.filetype
        if ft == "gitcommit" or ft == "gitrebase" then
            return
        end
        if vim.bo.buftype ~= "" then
            return
        end
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            if
                vim.api.nvim_get_option_value("filetype", { buf = vim.api.nvim_win_get_buf(w) }) == "snacks_picker_list"
            then
                return
            end
        end
        open_explorer_keep_focus()
    end,
})

autocmd({ "BufWinEnter", "WinEnter" }, {
    desc = "Reveal the current file in the explorer sidebar",
    group = group("explorer-follow", { clear = true }),
    callback = function()
        -- scheduled: on BufWinEnter the window still reports the outgoing buffer
        vim.schedule(function()
            pcall(function()
                require("lib.explorer").reveal_current()
            end)
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

-- undofile and shada registers would persist secret plaintext; shada is global, so only registers go
local function no_secret_history()
    vim.opt_local.undofile = false
    vim.opt_local.swapfile = false
    vim.opt.shada:prepend("<0")
end
local secret_history = group("no-secret-history", { clear = true })
autocmd({ "BufReadPre", "BufNewFile" }, {
    desc = "No undo/shada registers for secret files",
    group = secret_history,
    pattern = { "*/secrets/*", "*.sops.*", "*.env", "*.env.*", ".envrc", "*.gpg", "*.age", "*.asc" },
    callback = no_secret_history,
})
-- privymd decrypts ```gpg fences in place on read (scheduled, so this sees them first); it has no event of its own
autocmd("BufReadPost", {
    desc = "No undo/shada registers for markdown with privymd blocks",
    group = secret_history,
    pattern = "*.md",
    callback = function(args)
        for _, line in ipairs(vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)) do
            if line:match("^```+gpg%s*$") then
                return no_secret_history()
            end
        end
    end,
})

-- reapplied after every theme switch
autocmd({ "ColorScheme", "VimEnter" }, {
    desc = "Transparent separators and bars",
    group = group("transparent-bars", { clear = true }),
    callback = function()
        -- the theme's own dim shade, not a fixed color
        local dim = vim.api.nvim_get_hl(0, { name = "NonText", link = false }).fg
        local sep = vim.api.nvim_get_hl(0, { name = "WinSeparator", link = false }).fg
        vim.api.nvim_set_hl(0, "WinSeparator", { fg = dim or sep, ctermfg = 8 })
        for _, name in ipairs({ "BufferCurrent", "BufferOffset", "BufferVisible", "StatusLine" }) do
            local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
            hl.fg, hl.bg, hl.ctermfg, hl.ctermbg = nil, nil, nil, nil
            vim.api.nvim_set_hl(0, name, hl)
        end
    end,
})
