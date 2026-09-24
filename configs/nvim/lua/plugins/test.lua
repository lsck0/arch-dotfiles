return {
    {
        "nvim-neotest/neotest",                -- test runner framework
        dependencies = {
            "nvim-neotest/nvim-nio",           -- async IO library
            "nvim-lua/plenary.nvim",           -- Lua utility library
            "antoinemadec/FixCursorHold.nvim", -- CursorHold event fix
            "nvim-treesitter/nvim-treesitter", -- syntax parsing engine
            "nvim-neotest/neotest-python",     -- Python test adapter
            "rouge8/neotest-rust",             -- Rust test adapter
        },
        -- full key specs (with desc) so which-key shows them before neotest loads
        keys = {
            { "<leader>nr", function() require("neotest").run.run() end,                  desc = "Test nearest" },
            { "<leader>nf", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Test file" },
            { "<leader>na", function() require("neotest").run.run(vim.fn.getcwd()) end,    desc = "Test all" },
            { "<leader>nl", function() require("neotest").run.run_last() end,             desc = "Test last" },
            { "<leader>nd", function() require("neotest").run.run({ strategy = "dap" }) end, desc = "Debug nearest test" },
            { "<leader>ns", function() require("neotest").summary.toggle() end,           desc = "Test summary" },
            { "<leader>no", function() require("neotest").output.open({ enter = true }) end, desc = "Test output" },
            { "<leader>nw", function() require("neotest").watch.toggle() end,             desc = "Test watch (file)" },
            { "<leader>nx", function() require("neotest").run.stop() end,                 desc = "Test stop" },
        },
        config = function()
            require("neotest").setup({
                adapters = {
                    -- neotest-rust runs cargo-nextest (that's what the adapter is built on).
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
