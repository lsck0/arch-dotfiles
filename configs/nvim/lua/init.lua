vim.g.mapleader = " "
require "options"

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
    },

    defaults = { lazy = false },
    checker = { enabled = true, notify = false },
})

-- Apply the theme for the active wallpaper (lua/theme.lua + lua/themes/*.lua).
-- Must run AFTER lazy loads (theme plugins live in the lazy spec). Live
-- switches are handled by switch-wallpaper.sh's `nvim --server` nudge,
-- which calls the same require("theme").apply(name) this reads at startup.
require("theme").apply_from_marker()

require "autocmds"
require "filetype"
require "mappings"
require "snippets"

require "local_plugins.init"
