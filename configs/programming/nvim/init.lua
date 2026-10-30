vim.g.mapleader = " "
require("options")

-- before plugins so their startup messages land in it; pcall: absent before nvim 0.12
pcall(function()
    require("vim._core.ui2").enable({ msg = { targets = "msg" } })
end)

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
    local lazyrepo = "https://github.com/folke/lazy.nvim.git"
    local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({
            { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
            { out, "WarningMsg" },
            { "\nPress any key to exit..." },
        }, true, {})
        vim.fn.getchar()
        os.exit(1)
    end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    spec = {
        { "nvim-lua/plenary.nvim" },
        { import = "plugins" },
        { import = "languages" },
    },
    -- dot's plan-time probes set vim.g.dot_probe (--cmd): never clone missing plugins as a side effect of planning
    install = { missing = not vim.g.dot_probe },
})

require("theme").apply_from_marker()

require("autocmds")
require("filetype")
require("mappings")

require("local_plugins.init")
