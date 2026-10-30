local installed = require("lib.treesitter_parsers")

return {
    {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        event = { "BufReadPost", "BufNewFile" }, -- before FileType highlight
        cmd = { "TSUpdate", "TSInstall", "TSInstallSync" },
        build = ":TSUpdate",
        dependencies = {
            { "nvim-treesitter/nvim-treesitter-context" },
        },
        config = function()
            local treesitter = require("nvim-treesitter")
            -- setup() fires TSUpdate, so the parser autocmd goes first
            vim.api.nvim_create_autocmd("User", {
                group = vim.api.nvim_create_augroup("TreesitterCustomParsers", { clear = true }),
                pattern = "TSUpdate",
                callback = function()
                    local nya = require("lib.nya")
                    if nya then
                        require("nvim-treesitter.parsers").nya = { install_info = { path = nya } }
                    end
                    require("nvim-treesitter.parsers").jai = {
                        install_info = {
                            url = "https://github.com/constantitus/tree-sitter-jai",
                            revision = "96440b0f78a45bed1668d5693f26c0d30b4d1a84",
                        },
                    }
                end,
            })
            treesitter.setup()

            vim.api.nvim_create_user_command("TSInstallSync", function()
                treesitter.install(installed):wait()
            end, { desc = "Install configured parsers and wait" })

            -- lazy-loaded on a later buffer, VimEnter has already fired then
            if vim.v.vim_did_enter == 1 then
                treesitter.install(installed)
            else
                vim.api.nvim_create_autocmd("VimEnter", {
                    group = vim.api.nvim_create_augroup("TreesitterAutoInstall", { clear = true }),
                    once = true,
                    callback = function()
                        treesitter.install(installed)
                    end,
                })
            end
        end,
    },
}
