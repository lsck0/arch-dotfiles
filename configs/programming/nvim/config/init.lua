vim.g.mapleader = " "
require("options")

-- before plugins so their startup messages land in it; pcall: absent before nvim 0.12
pcall(function()
    require("vim._core.ui2").enable({ msg = { targets = "msg" } })
end)

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local lazy_missing = not vim.uv.fs_stat(lazypath)
-- dot's plan-time probes set vim.g.dot_probe (--cmd): they never touch the network, so without lazy no plugins load
if lazy_missing and vim.g.dot_probe then
    return
end
if lazy_missing then
    local lazyrepo = "https://github.com/folke/lazy.nvim.git"
    local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
    -- at its lazy-lock.json pin: lazy records its own commit there on the first start, so the newest stable would
    -- move the pin on every fresh install
    if vim.v.shell_error == 0 then
        local ok, lock = pcall(function()
            return vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath("config") .. "/lazy-lock.json"), "\n"))
        end)
        local pin = ok and lock["lazy.nvim"] and lock["lazy.nvim"].commit
        if pin then
            out = vim.fn.system({ "git", "-C", lazypath, "checkout", "--quiet", pin })
        end
    end
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({
            { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
            { out, "WarningMsg" },
        }, true, {})
        -- headless (dot's prefetch) has no key to press: waiting for one hangs it forever
        if #vim.api.nvim_list_uis() > 0 then
            vim.api.nvim_echo({ { "Press any key to exit..." } }, true, {})
            vim.fn.getchar()
        end
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
