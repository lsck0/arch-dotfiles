return {
    {
        "folke/todo-comments.nvim", -- highlight TODO comments
        event = "VeryLazy",
        config = function() require("todo-comments").setup() end
    },

    {
        "bngarren/checkmate.nvim", -- markdown checklist toggling
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
        "MeanderingProgrammer/render-markdown.nvim", -- inline markdown rendering
        ft = "markdown",
        dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" },
        config = function()
            require("render-markdown").enable()
            require("render-markdown").setup({
                completions = { lsp = { enabled = true } },
                -- "hide" conceals the fence rows, and snacks.image anchors mermaid diagrams to the opening fence, hiding them too.
                code = { border = "thin" },
                anti_conceal = {
                    ignore = {
                        code_background = true,
                        code_border = true,
                        code_language = true,
                    },
                },
            })
        end
    },

    {
        "nvim-orgmode/orgmode", -- org-mode note taking
        ft = "org",
        config = function()
            require("orgmode").setup({
                org_agenda_files = "~/orgfiles/**/*",
                org_default_notes_file = "~/orgfiles/refile.org",
            })
        end,
    },
}
