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
        -- the tree and terminals stay out of a session: a restore would bring the tree back as a file buffer and rerun
        -- a terminal's command (perf record, claude); the tree opens anew after the load
        config = function(_, opts)
            require("persistence").setup(opts)
            local group = vim.api.nvim_create_augroup("persistence-windows", { clear = true })
            vim.api.nvim_create_autocmd("User", {
                group = group,
                pattern = "PersistenceSavePre",
                callback = function()
                    for _, win in ipairs(vim.api.nvim_list_wins()) do
                        local buf = vim.api.nvim_win_get_buf(win)
                        if vim.bo[buf].filetype == "neo-tree" or vim.bo[buf].buftype == "terminal" then
                            -- the last window of the last tab stays, the session then holds an empty one
                            pcall(vim.api.nvim_win_close, win, true)
                        end
                    end
                end,
            })
            vim.api.nvim_create_autocmd("User", {
                group = group,
                pattern = "PersistenceLoadPost",
                callback = function()
                    require("lib.explorer").open()
                end,
            })
        end,
        keys = {
            { "<leader>qs", "<cmd>lua require('lib.session').load()<cr>", desc = "Restore session (cwd)" },
            { "<leader>qS", "<cmd>lua require('persistence').select()<cr>", desc = "Pick a session" },
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
