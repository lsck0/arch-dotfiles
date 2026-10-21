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
            {
                "<leader>nr",
                function()
                    require("neotest").run.run()
                end,
                desc = "Test nearest",
            },
            {
                "<leader>nf",
                function()
                    require("neotest").run.run(vim.fn.expand("%"))
                end,
                desc = "Test file",
            },
            {
                "<leader>na",
                function()
                    require("neotest").run.run(vim.fn.getcwd())
                end,
                desc = "Test all",
            },
            {
                "<leader>nl",
                function()
                    require("neotest").run.run_last()
                end,
                desc = "Test last",
            },
            {
                "<leader>nd",
                function()
                    require("neotest").run.run({ strategy = "dap" })
                end,
                desc = "Debug nearest test",
            },
            {
                "<leader>ns",
                function()
                    require("neotest").summary.toggle()
                end,
                desc = "Test summary",
            },
            {
                "<leader>no",
                function()
                    require("neotest").output.open({ enter = true })
                end,
                desc = "Test output",
            },
            {
                "<leader>nw",
                function()
                    require("neotest").watch.toggle()
                end,
                desc = "Test watch (file)",
            },
            {
                "<leader>nx",
                function()
                    require("neotest").run.stop()
                end,
                desc = "Test stop",
            },
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
