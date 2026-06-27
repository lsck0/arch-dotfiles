return {
    {
        "nvim-neotest/neotest",
        dependencies = {
            "nvim-neotest/nvim-nio",
            "nvim-lua/plenary.nvim",
            "antoinemadec/FixCursorHold.nvim",
            "nvim-treesitter/nvim-treesitter",
            "nvim-neotest/neotest-python",
            "rouge8/neotest-rust",
        },
        config = function()
            require("neotest").setup({
                adapters = {
                    require("neotest-rust"),
                    require("neotest-python")({
                        dap = { justMyCode = false },
                    }),
                },
            })

            local nt = require("neotest")
            local map = vim.keymap.set
            map("n", "<leader>nr", function() nt.run.run() end, { desc = "Test nearest" })
            map("n", "<leader>nf", function() nt.run.run(vim.fn.expand("%")) end, { desc = "Test file" })
            map("n", "<leader>na", function() nt.run.run(vim.fn.getcwd()) end, { desc = "Test all" })
            map("n", "<leader>nl", function() nt.run.run_last() end, { desc = "Test last" })
            map("n", "<leader>nd", function() nt.run.run({ strategy = "dap" }) end, { desc = "Debug nearest test" })
            map("n", "<leader>ns", function() nt.summary.toggle() end, { desc = "Test summary" })
            map("n", "<leader>no", function() nt.output.open({ enter = true }) end, { desc = "Test output" })
            map("n", "<leader>nw", function() nt.watch.toggle() end, { desc = "Test watch (file)" })
            map("n", "<leader>nx", function() nt.run.stop() end, { desc = "Test stop" })
        end,
    },
}
