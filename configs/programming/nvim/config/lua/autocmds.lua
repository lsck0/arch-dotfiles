local autocmd = vim.api.nvim_create_autocmd
local group = vim.api.nvim_create_augroup

autocmd("TextYankPost", {
    desc = "Highlight when yanking text",
    group = group("highlight-yank", { clear = true }),
    callback = function()
        vim.hl.on_yank()
    end,
})

local PROSE = { "markdown", "text", "gitcommit", "tex", "plaintex", "rst", "org", "typst", "mail" }
local SPELLED = { markdown = true, gitcommit = true, text = true, tex = true, plaintex = true, org = true }

autocmd("FileType", {
    desc = "Prose: hard-wrap at textwidth, soft-wrap what is longer than the window, spell-check",
    group = group("prose", { clear = true }),
    pattern = PROSE,
    callback = function(args)
        vim.opt_local.textwidth = 120
        -- a pasted paragraph or a window narrower than textwidth still reads: wrapped at words, indent kept
        vim.opt_local.wrap = true
        vim.opt_local.linebreak = true
        vim.opt_local.breakindent = true
        vim.opt_local.formatoptions:append("tn")
        if SPELLED[vim.bo[args.buf].filetype] then
            vim.opt_local.spell = true
            vim.opt_local.spelllang = require("lib.dot_options").spell_languages
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

local NUMBERTOGGLE_ACTIVE = { BufEnter = true, FocusGained = true, InsertLeave = true, WinEnter = true }
autocmd({ "BufEnter", "FocusGained", "InsertLeave", "WinEnter", "BufLeave", "FocusLost", "InsertEnter", "WinLeave" }, {
    desc = "Relative line numbers when active, absolute when inactive",
    group = group("numbertoggle", { clear = true }),
    callback = function(args)
        if not vim.wo.number then
            return
        end
        if NUMBERTOGGLE_ACTIVE[args.event] then
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
        -- tex keeps vim syntax: vimtex's mathzone detection needs it
        if ft == "tex" or ft == "plaintex" or ft == "bib" then
            return
        end
        local lang = vim.treesitter.language.get_lang(ft) or ft
        if not pcall(vim.treesitter.start, buf, lang) then
            return
        end
        -- prose keeps the runtime indent script (make's recipe tabs)
        if vim.treesitter.query.get(lang, "indents") and not vim.tbl_contains(PROSE, ft) then
            vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
    end,
})

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
        if vim.g.started_by_firenvim or vim.env.NVIM_TMS ~= "1" or vim.fn.argc() > 1 or vim.bo.buftype ~= "" then
            return
        end
        if vim.bo.filetype == "gitcommit" or vim.bo.filetype == "gitrebase" then
            return
        end
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_get_option_value("filetype", { buf = vim.api.nvim_win_get_buf(w) }) == "neo-tree" then
                return
            end
        end
        open_explorer_keep_focus()
    end,
})

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

-- Undofile and shada registers would persist secret plaintext; shada is global, so only registers go.
local function no_secret_history()
    vim.opt_local.undofile = false
    vim.opt_local.swapfile = false
    -- gpg.nvim empties shada after a .gpg read, and a lone "<0" is invalid (E528); "<0" also must not stack
    local shada = vim.o.shada
    if shada ~= "" and not shada:match("^<0,") then
        vim.opt.shada:prepend("<0")
    end
end
local secret_history = group("no-secret-history", { clear = true })
autocmd({ "BufReadPre", "BufNewFile" }, {
    desc = "No undo/shada registers for secret files",
    group = secret_history,
    pattern = { "*/secrets/*", "*.sops.*", "*.env", "*.env.*", ".envrc", "*.gpg", "*.age", "*.asc" },
    callback = no_secret_history,
})
-- privymd decrypts ```gpg fences in place on read (scheduled, so this sees them first) and has no event of its own
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

-- a NUL in the first block is binary, as git and grep decide it; UTF-8 and latin1 text has none. The buffer is read,
-- not the file: gpg and sops buffers hold the decrypted text.
local BINARY_PROBE_BYTES = 8192
local function buffer_has_nul(buf)
    local bytes = 0
    for row = 0, vim.api.nvim_buf_line_count(buf) - 1 do
        local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, true)[1]
        if line:find("\0", 1, true) then
            return true
        end
        bytes = bytes + #line + 1
        if bytes >= BINARY_PROBE_BYTES then
            return false
        end
    end
    return false
end

autocmd("BufReadPost", {
    desc = "Open binary files read-only",
    group = group("binary-detect", { clear = true }),
    callback = function(args)
        -- 'binary' set: opened with -b or ++bin on purpose
        if vim.bo[args.buf].buftype ~= "" or vim.bo[args.buf].binary or not buffer_has_nul(args.buf) then
            return
        end
        vim.bo[args.buf].readonly = true
        vim.notify(vim.fn.fnamemodify(args.file, ":~:.") .. ": binary, read-only; :Hex shows a hex dump")
    end,
})

vim.api.nvim_create_user_command("Hex", function()
    local path = vim.api.nvim_buf_get_name(0)
    if path == "" or vim.bo.buftype ~= "" then
        return vim.notify("Hex: not a file buffer", vim.log.levels.ERROR)
    end
    -- a second :Hex goes to the open dump: its buffer name is taken while it is shown
    local name = "xxd://" .. path
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == name then
            return vim.api.nvim_set_current_win(win)
        end
    end
    local dump = vim.system({ "xxd", path }, { text = true }):wait()
    if dump.code ~= 0 then
        return vim.notify("Hex: " .. vim.trim(dump.stderr), vim.log.levels.ERROR)
    end
    vim.cmd.vnew()
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].buflisted = false
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(dump.stdout, "\n", { trimempty = true }))
    vim.api.nvim_buf_set_name(buf, name)
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = "xxd"
end, { desc = "Hex dump of the file (xxd) in a read-only split" })
