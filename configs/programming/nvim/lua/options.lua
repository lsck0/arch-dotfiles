local set = vim.opt

set.clipboard = "unnamedplus"

set.spellfile = vim.fn.stdpath("config") .. "/spell/en.utf-8.add"
set.spellcapcheck = ""
-- GitHub is checked as Git + Hub; not noplainbuffer: .txt has no syntax, so it would never be checked
set.spelloptions = "camel"
do
    local add = vim.uv.fs_stat(vim.o.spellfile)
    local spl = vim.uv.fs_stat(vim.o.spellfile .. ".spl")
    if add and (not spl or spl.mtime.sec < add.mtime.sec) then
        vim.cmd("silent! mkspell! " .. vim.fn.fnameescape(vim.o.spellfile))
    end
end

-- over ssh both ways go through the local terminal: ghostty answers osc 52 reads (clipboard-read = allow)
if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
    local osc = require("vim.ui.clipboard.osc52")
    vim.g.clipboard = {
        name = "OSC 52",
        copy = { ["+"] = osc.copy("+"), ["*"] = osc.copy("*") },
        paste = { ["+"] = osc.paste("+"), ["*"] = osc.paste("*") },
    }
end
set.cmdheight = 0
set.colorcolumn = "120"
set.cursorline = true
set.expandtab = true
set.fillchars = { eob = " " }
do
    -- the font beside the palette (configs/core/wallust/font.nu), for neovide
    set.guifont = "Kode Mono:h16"
    local f = io.open((vim.env.XDG_CACHE_HOME or vim.env.HOME .. "/.cache") .. "/wal/font.json")
    if f then
        local ok, font = pcall(vim.json.decode, f:read("*a"))
        f:close()
        if ok and type(font) == "table" and font.mono and font.size then
            set.guifont = font.mono .. ":h" .. font.size
        end
    end
end
set.ignorecase = true
set.inccommand = "split"
set.list = true
set.listchars = { tab = "> ", trail = "-", eol = "\u{21b2}" }
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
set.softtabstop = -1 -- follow shiftwidth, so <BS> respects a filetype's indent width
set.splitbelow = true
set.splitkeep = "screen"
set.splitright = true
set.swapfile = false
set.tabstop = 4
set.termguicolors = true
set.timeoutlen = 200
set.undofile = true
set.undolevels = 10000
set.updatetime = 250
set.virtualedit = "block"
set.winborder = "rounded"
set.wrap = false
set.modeline = false -- security: no option execution from opened files

vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

if vim.g.neovide then
    vim.g.neovide_scale_factor = 1.0
    vim.g.neovide_theme = "auto"
    -- opacity comes from Hyprland's windowrule (OPACITY_SURFACE), same as every other app; not set here to avoid stacking
    vim.g.neovide_remember_window_size = true
    vim.g.neovide_hide_mouse_when_typing = true
    vim.g.neovide_refresh_rate = 120
    vim.g.neovide_refresh_rate_idle = 5
    vim.g.neovide_cursor_animation_length = 0.05
    vim.g.neovide_cursor_trail_size = 0.0
    vim.g.neovide_cursor_vfx_mode = ""
    vim.g.neovide_padding_top = 4
    vim.g.neovide_padding_bottom = 4
    vim.g.neovide_padding_left = 6
    vim.g.neovide_padding_right = 6
    vim.g.neovide_floating_blur_amount_x = 2.0
    vim.g.neovide_floating_blur_amount_y = 2.0
    vim.g.neovide_scroll_animation_length = 0.0
end
