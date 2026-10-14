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
        config = function()
            -- no top winbar, lualine renders it
            require("dropbar").setup({ bar = { enable = false } })
        end,
    },

    {
        "kevinhwang91/nvim-ufo",
        dependencies = { "kevinhwang91/promise-async" },
        event = { "BufReadPost", "BufNewFile" },
        keys = {
            {
                "zR",
                function()
                    require("ufo").openAllFolds()
                end,
                desc = "Open all folds",
            },
            {
                "zM",
                function()
                    require("ufo").closeAllFolds()
                end,
                desc = "Close all folds",
            },
        },
        init = function()
            -- start unfolded; ufo drives folding from here
            vim.o.foldcolumn = "0"
            vim.o.foldlevel = 99
            vim.o.foldlevelstart = 99
            vim.o.foldenable = true
        end,
        config = function()
            require("ufo").setup({
                provider_selector = function()
                    return { "treesitter", "indent" }
                end,
            })
        end,
    },

    {
        "folke/persistence.nvim",
        event = "BufReadPre",
        opts = {},
        keys = {
            {
                "<leader>qs",
                function()
                    require("persistence").load()
                end,
                desc = "Restore session (cwd)",
            },
            {
                "<leader>ql",
                function()
                    require("persistence").load({ last = true })
                end,
                desc = "Restore last session",
            },
            {
                "<leader>qd",
                function()
                    require("persistence").stop()
                end,
                desc = "Stop saving session",
            },
        },
    },

    {
        "j-hui/fidget.nvim",
        event = "LspAttach",
        opts = {},
    },
}
