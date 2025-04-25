local set = vim.opt

set.clipboard = "unnamedplus"
set.cmdheight = 0
set.colorcolumn = "120"
set.cursorline = true
set.expandtab = true
set.fillchars = { eob = " " }
set.guifont = "Terminus (TTF):h22"
set.laststatus = 3
set.mousemoveevent = true
set.number = true
set.relativenumber = true
set.scrolloff = 8
set.shell = "zsh"
set.shiftwidth = 4
set.showtabline = 2
set.signcolumn = "yes"
set.smartindent = true
set.softtabstop = 4
set.splitkeep = "screen"
set.tabstop = 4
set.termguicolors = true
set.timeout = true
set.timeoutlen = 400
set.wrap = false

-- wsl clipboard sync
if vim.fn.has('wsl') == 1 then
    vim.g.clipboard = {
        name = 'WslClipboard',
        copy = {
            ['+'] = 'clip.exe',
            ['*'] = 'clip.exe',
        },
        paste = {
            ['+'] = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
            ['*'] = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
        },
        cache_enabled = 0,
    }
end
