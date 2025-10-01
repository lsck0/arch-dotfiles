return {
    {
        "folke/todo-comments.nvim",
        config = function() require("todo-comments").setup() end
    },

    {
        "bngarren/checkmate.nvim",
        ft = "markdown",
        opts = {
            keys = {
                ["<C-Space>"] = {
                    rhs = "<cmd>Checkmate toggle<CR>",
                    desc = "Toggle todo item",
                    modes = { "n", "v" },
                },
            },
        },
    },

    {
        "MeanderingProgrammer/render-markdown.nvim",
        dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" },
        ft = "markdown",
        config = function()
            require("render-markdown").enable()
            require("render-markdown").setup({
                completions = { lsp = { enabled = true } },
            })
        end
    },

    {
        "nvim-neorg/neorg",
        version = "*",
        config = function()
            require('neorg').setup({
                load = {
                    ["core.defaults"] = {},
                    ["core.concealer"] = {},
                    ["core.completion"] = {
                        config = {
                            engine = "nvim-cmp",
                        }
                    }
                },
            })
        end
    },

    { "vimwiki/vimwiki" },
}
