return {
    {
        "nvim-neotest/neotest", -- test runner framework
        dependencies = {
            "nvim-neotest/nvim-nio", -- async IO library
            "nvim-lua/plenary.nvim", -- Lua utility library
            "antoinemadec/FixCursorHold.nvim", -- CursorHold event fix
            "nvim-treesitter/nvim-treesitter", -- syntax parsing engine
            "nvim-neotest/neotest-python", -- Python test adapter
            "rouge8/neotest-rust", -- Rust test adapter
        },
        -- keymaps below are all set inside config(), so this list is what
        -- actually defers loading until one of them is first pressed
        keys = {
            "<leader>nr", "<leader>nf", "<leader>na", "<leader>nl", "<leader>nd",
            "<leader>ns", "<leader>no", "<leader>nw", "<leader>nx",
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
