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
                { "<leader>p", group = "present" },
                { "<leader>s", group = "search/spectre" },
                { "<leader>b", group = "breakpoints" },
                { "<leader>g", group = "git" },
                { "<leader>t", group = "trouble" },
                { "<leader>v", group = "venn" },
                { "<leader>x", desc = "Comment line" },
            })
        end,
    },
}
