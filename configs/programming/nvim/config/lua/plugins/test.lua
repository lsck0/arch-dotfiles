return {
    {
        "nvim-neotest/neotest",
        dependencies = {
            "nvim-neotest/nvim-nio",
            "nvim-lua/plenary.nvim",
            "nvim-treesitter/nvim-treesitter",
            "nvim-neotest/neotest-python",
            "rouge8/neotest-rust",
        },
        keys = {
            { "<leader>nr", "<cmd>lua require('neotest').run.run()<cr>", desc = "Test nearest" },
            { "<leader>nf", "<cmd>lua require('neotest').run.run(vim.fn.expand('%'))<cr>", desc = "Test file" },
            { "<leader>na", "<cmd>lua require('neotest').run.run(vim.fn.getcwd())<cr>", desc = "Test all" },
            { "<leader>nl", "<cmd>lua require('neotest').run.run_last()<cr>", desc = "Test last" },
            {
                "<leader>nd",
                "<cmd>lua require('neotest').run.run({ strategy = 'dap' })<cr>",
                desc = "Debug nearest test",
            },
            { "<leader>ns", "<cmd>lua require('neotest').summary.toggle()<cr>", desc = "Test summary" },
            { "<leader>no", "<cmd>lua require('neotest').output.open({ enter = true })<cr>", desc = "Test output" },
            { "<leader>nw", "<cmd>lua require('neotest').watch.toggle()<cr>", desc = "Test watch (file)" },
            { "<leader>nx", "<cmd>lua require('neotest').run.stop()<cr>", desc = "Test stop" },
        },
        config = function()
            require("neotest").setup({
                adapters = {
                    require("neotest-rust")({
                        args = { "--no-fail-fast" },
                        dap_adapter = "codelldb",
                    }),
                    require("neotest-python")({
                        dap = { justMyCode = false },
                    }),
                },
            })
        end,
    },
}
