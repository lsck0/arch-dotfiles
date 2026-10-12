return {
    {
        "folke/which-key.nvim", -- keybinding hint popup
        event = "VeryLazy",
        opts = {
            preset = "modern",
            delay = 200,
            icons = { mappings = false },
        },
        config = function(_, opts)
            local wk = require("which-key")
            wk.setup(opts)
            wk.add({
                { "<leader>f", group = "find" },
                { "<leader>l", group = "lsp" },
                { "<leader>d", group = "debug" },
                { "<leader>n", group = "test" },
                { "<leader>j", group = "jupyter" },
                { "<leader>p", group = "profiling" },
                { "<leader>s", group = "search/replace" },
                { "<leader>g", group = "git" },
                { "<leader>k", group = "keys/secrets" },
                { "<leader>t", group = "trouble" },
                { "<leader>T", group = "taskwarrior" },
                { "<leader>q", group = "session" },
                { "<leader>c", group = "claude" },
                { "<leader>C", group = "comment/doc" },
                { "<leader>o", group = "github" },
                { "<leader>m", group = "orgmode" },
                { "<leader>r", group = "rest" },
                { "<leader>u", desc = "Undotree" }, -- its keymap sets no desc of its own
            })
        end,
    },
}
