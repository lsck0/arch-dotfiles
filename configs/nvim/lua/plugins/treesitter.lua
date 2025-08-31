return {
    {
        "nvim-treesitter/nvim-treesitter",
        lazy = false,
        build = ":TSUpdate",
        dependencies = {
            { "nvim-treesitter/nvim-treesitter-context" },
            -- {
            --     "code-biscuits/nvim-biscuits",
            --     config = function()
            --         require("nvim-biscuits").setup({
            --             min_distance = 20,
            --         })
            --     end,
            -- },
        },
        config = function()
            require("nvim-treesitter.configs").setup({
                ensure_installed = {
                    "bash",
                    "c",
                    "cmake",
                    "cpp",
                    "css",
                    "dockerfile",
                    "haskell",
                    "html",
                    "java",
                    "javascript",
                    "json",
                    "lua",
                    "luadoc",
                    "make",
                    "norg",
                    "ocaml",
                    "printf",
                    "python",
                    "query",
                    "rust",
                    "scss",
                    "sql",
                    "toml",
                    "typescript",
                    "vim",
                    "vimdoc",
                    "yaml",
                },
                sync_install = false,
                auto_install = true,

                highlight = {
                    enable = true,
                    use_languagetree = true,
                    additional_vim_regex_highlighting = false,
                },

                indent = {
                    enable = true,
                },
            })
        end,
    },
}
