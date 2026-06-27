return {
    {
        "folke/which-key.nvim",
        opts = {
            preset = "modern",
            delay = 200,
            icons = { mappings = false },
        },
        config = function(_, opts)
            local wk = require("which-key")
            wk.setup(opts)
            -- leader prefix group labels
            wk.add({
                { "<leader>f", group = "find" },
                { "<leader>l", group = "lsp" },
                { "<leader>d", group = "debug" },
                { "<leader>n", group = "test" },
                { "<leader>s", group = "search" },
            })
        end,
    },
}
