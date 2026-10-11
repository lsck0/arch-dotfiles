return {
    {
        "ej-shafran/compile-mode.nvim", -- Emacs-style compile mode
        branch = "latest",
        cmd = { "Compile", "Recompile" },
        dependencies = {
            { "m00qek/baleia.nvim", tag = "v1.3.0" }, -- ANSI color rendering
        },
        config = function()
            vim.g.compile_mode = {
                ansi_color = { kind = "render" },
            }
        end
    },

    {
        "MagicDuck/grug-far.nvim", -- fast project-wide search/replace, live preview
        cmd = "GrugFar",
        opts = {},
    },

    {
        -- upstream is public again at dont-be-evil-company; no longer vendored
        "dont-be-evil-company/kulala.nvim", -- REST client
        ft = { "http", "rest" },
        opts = {
            global_keymaps = true,
            global_keymaps_prefix = "<leader>r",
            kulala_keymaps_prefix = "",
            -- let kulala download, build and install its own kulala_http parser + queries (needs tree-sitter-cli,
            -- which is in programming/packages.txt). Replaces the parser/ and queries/ copies we used to vendor.
            treesitter = { enable = true },
        },
    },

    {
        "jiaoshijie/undotree",                  -- undo history tree
        dependencies = "nvim-lua/plenary.nvim",
        config = true,
        keys = {
            { "<leader>u", "<cmd>lua require('undotree').toggle()<cr>" },
        },
    },

    {
        "piersolenski/import.nvim", -- auto-import symbols
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
        "olrtg/nvim-emmet", -- emmet abbreviations
        config = function()
            vim.keymap.set({ "n", "v" }, "<leader>E", require("nvim-emmet").wrap_with_abbreviation,
                { desc = "Emmet wrap with abbreviation" })
        end,
    },
}
