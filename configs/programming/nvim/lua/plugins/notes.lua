return {
    {
        "folke/todo-comments.nvim",
        event = "VeryLazy",
        opts = {},
    },

    {
        "bngarren/checkmate.nvim",
        ft = "markdown",
        opts = {
            files = {
                "*.md",
            },
            keys = {
                ["<C-Space>"] = {
                    rhs = "<cmd>Checkmate cycle_next<CR>",
                    desc = "Cycle todo item(s) to the next state",
                    modes = { "n", "v" },
                },
            },
            todo_states = {
                unchecked = { marker = "\u{25a1}" },
                checked = { marker = "\u{2714}" },
            },
        },
    },

    {
        "MeanderingProgrammer/render-markdown.nvim",
        ft = "markdown",
        dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" },
        config = function()
            require("render-markdown").setup({
                completions = { lsp = { enabled = true } },
                -- not "hide": mermaid images anchor to the fence and would vanish
                code = { border = "thin" },
                anti_conceal = {
                    ignore = {
                        code_background = true,
                        code_border = true,
                        code_language = true,
                    },
                },
            })
        end,
    },

    {
        "nvim-orgmode/orgmode",
        ft = "org",
        opts = {
            org_agenda_files = "~/orgfiles/**/*",
            org_default_notes_file = "~/orgfiles/refile.org",
            mappings = { prefix = "<leader>m" },
        },
    },
}
