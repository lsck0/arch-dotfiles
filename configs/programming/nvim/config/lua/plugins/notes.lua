return {
    {
        "folke/todo-comments.nvim",
        event = "VeryLazy",
        opts = {},
    },

    {
        -- calls the table form of vim.validate (removed at nvim 1.0); kept, waiting on upstream, no report filed by us
        "bngarren/checkmate.nvim",
        ft = "markdown",
        opts = {
            files = { "*.md" },
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
        opts = {
            completions = { lsp = { enabled = true } },
            -- not "hide": mermaid images anchor to the fence and would vanish
            code = { border = "thin" },
            anti_conceal = { ignore = { code_background = true, code_border = true, code_language = true } },
        },
    },

    {
        "nvim-orgmode/orgmode",
        ft = "org",
        cmd = "Org",
        -- the global keys of its <leader>m prefix, reachable before an org file was opened
        keys = {
            { "<leader>ma", "<cmd>lua require('orgmode').action('agenda.prompt')<cr>", desc = "org agenda" },
            { "<leader>mc", "<cmd>lua require('orgmode').action('capture.prompt')<cr>", desc = "org capture" },
        },
        opts = {
            org_agenda_files = "~/sync/notes/**/*.org",
            org_default_notes_file = "~/sync/notes/refile.org",
            mappings = { prefix = "<leader>m" },
        },
    },
}
