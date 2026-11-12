return {
    {
        "ej-shafran/compile-mode.nvim",
        branch = "latest",
        cmd = { "Compile", "Recompile" },
        dependencies = { "m00qek/baleia.nvim" },
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
        -- its kulala-fmt submodule fails to check out from a newer clone; kulala-fmt is a system package
        submodules = false,
        ft = { "http", "rest" },
        keys = {
            { "<leader>rb", "<cmd>lua require('kulala').scratchpad()<cr>", desc = "Open scratchpad" },
            { "<leader>ro", "<cmd>lua require('kulala').open()<cr>", desc = "Open kulala" },
        },
        opts = {
            -- the rest of <leader>r; the two keys above only load kulala outside http buffers
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
            { "<leader>u", "<cmd>lua require('undotree').toggle()<cr>", desc = "Undotree" },
        },
    },

    {
        "piersolenski/import.nvim",
        opts = { picker = "telescope" },
        keys = {
            { "<leader>i", "<cmd>lua require('import').pick()<cr>", desc = "Import" },
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
