vim.g.mapleader = " "
require "options"

-- built-in message ui, before plugins so their startup messages land in it; pcall: absent before nvim 0.12
-- msg target: with cmdheight=0 the cmd target expands the cmdline for every message
pcall(function() require("vim._core.ui2").enable({ msg = { targets = "msg" } }) end)

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazyrepo = "https://github.com/folke/lazy.nvim.git"
    local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({
            { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
            { out,                            "WarningMsg" },
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

    defaults = { lazy = false },
    -- off: background git fetches slow startup
    checker = { enabled = false, notify = false },
})

require("theme").apply_from_marker()

require "autocmds"
require "filetype"
require "mappings"
require "snippets"

require "local_plugins.init"
