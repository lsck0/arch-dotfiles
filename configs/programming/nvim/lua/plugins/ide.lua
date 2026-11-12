return {
    {
        "stevearc/aerial.nvim",
        cmd = { "AerialToggle", "AerialOpen", "AerialNavToggle" },
        keys = {
            { "<leader>lc", "<cmd>AerialToggle<cr>", desc = "Code outline (aerial)" },
        },
        dependencies = {
            "nvim-treesitter/nvim-treesitter",
            "nvim-tree/nvim-web-devicons",
        },
        opts = {
            backends = { "lsp", "treesitter", "markdown", "man" },
            layout = { default_direction = "right", min_width = 30 },
            show_guides = true,
            -- all kinds, else a file of #defines reports no symbols
            filter_kind = false,
        },
    },

    {
        "Bekaboo/dropbar.nvim",
        event = "VeryLazy",
        dependencies = { "nvim-telescope/telescope-fzf-native.nvim" },
        opts = { bar = { enable = false } },
    },

    {
        "kevinhwang91/nvim-ufo",
        dependencies = { "kevinhwang91/promise-async" },
        event = { "BufReadPost", "BufNewFile" },
        keys = {
            { "zR", "<cmd>lua require('ufo').openAllFolds()<cr>", desc = "Open all folds" },
            { "zM", "<cmd>lua require('ufo').closeAllFolds()<cr>", desc = "Close all folds" },
        },
        init = function()
            vim.o.foldcolumn = "0"
            vim.o.foldlevel = 99
            vim.o.foldlevelstart = 99
            vim.o.foldenable = true
        end,
        opts = {
            provider_selector = function()
                return { "treesitter", "indent" }
            end,
        },
    },

    {
        "folke/persistence.nvim",
        event = "BufReadPre",
        opts = {},
        keys = {
            { "<leader>qs", "<cmd>lua require('persistence').load()<cr>", desc = "Restore session (cwd)" },
            {
                "<leader>ql",
                "<cmd>lua require('persistence').load({ last = true })<cr>",
                desc = "Restore last session",
            },
            { "<leader>qd", "<cmd>lua require('persistence').stop()<cr>", desc = "Stop saving session" },
        },
    },

    {
        "j-hui/fidget.nvim",
        event = "LspAttach",
        opts = {},
    },
}
