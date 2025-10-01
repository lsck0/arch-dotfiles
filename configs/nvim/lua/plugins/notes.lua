return {
    {
        "folke/todo-comments.nvim",
        config = function() require("todo-comments").setup() end
    },

    {
        "bngarren/checkmate.nvim",
        ft = "markdown",
        opts = {
            files = {
                "*.md"
            },
            keys = {
                ["<C-Space>"] = {
                    rhs = "<cmd>Checkmate cycle_next<CR>",
                    desc = "Cycle todo item(s) to the next state",
                    modes = { "n", "v" },
                },
            },
            todo_states = {
                unchecked = { marker = "□" },
                checked = { marker = "✔" },
            }
        },
    },

    {
        "MeanderingProgrammer/render-markdown.nvim",
        dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" },
        config = function()
            require("render-markdown").enable()
            require("render-markdown").setup({
                completions = { lsp = { enabled = true } },
            })
        end
    },

    {
        "nvim-orgmode/orgmode",
        ft = { "org" },
        config = function()
            require("orgmode").setup({
                org_agenda_files = "~/orgfiles/**/*",
                org_default_notes_file = "~/orgfiles/refile.org",
            })
        end,
    }
}
