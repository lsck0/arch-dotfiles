return {
    {
        "ej-shafran/compile-mode.nvim",
        branch = "latest",
        cmd = { "Compile", "Recompile" },
        dependencies = {
            { "m00qek/baleia.nvim", tag = "v1.3.0" },
        },
        config = function()
            vim.g.compile_mode = {
                ansi_color = { kind = "render" },
            }
        end,
    },

    {
        "MagicDuck/grug-far.nvim",
        cmd = "GrugFar",
        opts = {},
    },

    {
        "dont-be-evil-company/kulala.nvim",
        -- last pure-lua release: later ones need a kulala-core binary behind a license token
        tag = "v5.3.4",
        -- checking out its kulala-fmt submodule from a newer clone fails; kulala-fmt is a system package
        submodules = false,
        ft = { "http", "rest" },
        keys = {
            {
                "<leader>rb",
                function()
                    require("kulala").scratchpad()
                end,
                desc = "Open scratchpad",
            },
            {
                "<leader>ro",
                function()
                    require("kulala").open()
                end,
                desc = "Open kulala",
            },
            {
                "<leader>rs",
                function()
                    require("kulala").run()
                end,
                mode = { "n", "v" },
                desc = "Send request",
            },
            {
                "<leader>ra",
                function()
                    require("kulala").run_all()
                end,
                mode = { "n", "v" },
                desc = "Send all requests",
            },
            {
                "<leader>rr",
                function()
                    require("kulala").replay()
                end,
                desc = "Replay the last request",
            },
        },
        opts = {
            global_keymaps = true,
            global_keymaps_prefix = "<leader>r",
            kulala_keymaps_prefix = "",
        },
    },

    {
        "jiaoshijie/undotree",
        dependencies = "nvim-lua/plenary.nvim",
        config = true,
        keys = {
            { "<leader>u", "<cmd>lua require('undotree').toggle()<cr>" },
        },
    },

    {
        "piersolenski/import.nvim",
        opts = {
            picker = "telescope",
        },
        keys = {
            {
                "<leader>i",
                function()
                    require("import").pick()
                end,
                desc = "Import",
            },
        },
    },

    {
        "olrtg/nvim-emmet",
        config = function()
            vim.keymap.set(
                { "n", "v" },
                "<leader>E",
                require("nvim-emmet").wrap_with_abbreviation,
                { desc = "Emmet wrap with abbreviation" }
            )
        end,
    },
}
