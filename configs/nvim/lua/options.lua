-- Silence a third-party plugin's deprecated vim.lsp.buf_get_clients() warning
local _deprecate = vim.deprecate
vim.deprecate = function(name, ...)
    if type(name) == "string" and name:find("buf_get_clients") then return end
    return _deprecate(name, ...)
end

local set = vim.opt

set.clipboard = "unnamedplus"

-- Over SSH, yank to the local terminal's clipboard via OSC 52.
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
    vim.g.neovide_theme = "auto"
    vim.g.neovide_remember_window_size = true
    vim.g.neovide_hide_mouse_when_typing = true
    vim.g.neovide_refresh_rate = 120
    vim.g.neovide_refresh_rate_idle = 5
    vim.g.neovide_cursor_animation_length = 0.05
    vim.g.neovide_cursor_trail_size = 0.3
    vim.g.neovide_cursor_vfx_mode = "railgun"
    vim.g.neovide_padding_top = 4
    vim.g.neovide_padding_bottom = 4
    vim.g.neovide_padding_left = 6
    vim.g.neovide_padding_right = 6
    vim.g.neovide_floating_blur_amount_x = 2.0
    vim.g.neovide_floating_blur_amount_y = 2.0
    vim.g.neovide_scroll_animation_length = 0.0 -- no smooth scroll
end
