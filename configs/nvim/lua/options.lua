local set = vim.opt

set.clipboard = "unnamedplus"
set.cmdheight = 0
set.colorcolumn = "120"
set.cursorline = true
set.expandtab = true
set.fillchars = { eob = " " }
set.guifont = "0xProto Nerd Font:h16"
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

if vim.g.neovide then
    vim.g.neovide_scale_factor = 1.0
end
