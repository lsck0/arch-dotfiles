-- silence a plugin's deprecated buf_get_clients() warning
local _deprecate = vim.deprecate
vim.deprecate = function(name, ...)
    if type(name) == "string" and name:find("buf_get_clients") then return end
    return _deprecate(name, ...)
end

local set = vim.opt

set.clipboard = "unnamedplus"

-- synced project wordlist for spell; zg/zw persist here into the dotfiles repo
set.spellfile = vim.fn.stdpath("config") .. "/spell/en.utf-8.add"
-- no sentence-start capitalization warnings
set.spellcapcheck = ""
-- GitHub is checked as Git + Hub; not noplainbuffer: .txt has no syntax, so it would never be checked at all
set.spelloptions = "camel"
-- the .spl is gitignored: rebuild it when a pulled wordlist is newer, else the synced words stay flagged
do
    local add = vim.uv.fs_stat(vim.o.spellfile)
    local spl = vim.uv.fs_stat(vim.o.spellfile .. ".spl")
    if add and (not spl or spl.mtime.sec < add.mtime.sec) then
        vim.cmd("silent! mkspell! " .. vim.fn.fnameescape(vim.o.spellfile))
    end
end

-- over ssh, yank to the local clipboard via osc 52
if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
    local osc = require("vim.ui.clipboard.osc52")
    local function from_reg()
        return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
    end
    vim.g.clipboard = {
        name = "OSC 52",
        copy = { ["+"] = osc.copy("+"), ["*"] = osc.copy("*") },
        paste = { ["+"] = from_reg, ["*"] = from_reg },
    }
end
set.cmdheight = 0
set.colorcolumn = "120"
set.cursorline = true
set.expandtab = true
set.fillchars = { eob = " " }
set.guifont = "Kode Mono:h16"
set.ignorecase = true
set.inccommand = "split"
set.laststatus = 3
set.mousemoveevent = true
set.number = true
set.pumheight = 12
set.relativenumber = true
set.scrolloff = 8
set.shell = "zsh"
set.shiftwidth = 4
set.showtabline = 2
set.signcolumn = "yes"
set.smartcase = true
set.smartindent = true
set.softtabstop = 4
set.splitbelow = true
set.splitkeep = "screen"
set.splitright = true
set.swapfile = false
set.tabstop = 4
set.termguicolors = true
set.timeout = true
set.timeoutlen = 200
set.undofile = true
set.undolevels = 10000
set.updatetime = 250
set.virtualedit = "block"
set.winborder = "rounded"
set.wrap = false
set.modeline = false -- security: no option execution from opened files

-- unused providers: skip the startup rplugin scan
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

if vim.g.neovide then
    vim.g.neovide_scale_factor = 1.0
    vim.g.neovide_theme = "auto"
    vim.g.neovide_remember_window_size = true
    vim.g.neovide_hide_mouse_when_typing = true
    vim.g.neovide_refresh_rate = 120
    vim.g.neovide_refresh_rate_idle = 5
    vim.g.neovide_cursor_animation_length = 0.05
    vim.g.neovide_cursor_trail_size = 0.0
    vim.g.neovide_cursor_vfx_mode = "" -- no particle trail dots
    vim.g.neovide_padding_top = 4
    vim.g.neovide_padding_bottom = 4
    vim.g.neovide_padding_left = 6
    vim.g.neovide_padding_right = 6
    vim.g.neovide_floating_blur_amount_x = 2.0
    vim.g.neovide_floating_blur_amount_y = 2.0
    vim.g.neovide_scroll_animation_length = 0.0 -- no smooth scroll
end
