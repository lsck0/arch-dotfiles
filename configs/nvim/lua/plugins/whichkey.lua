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
                { "<leader>s", group = "search" },
            })
        end,
    },
}
