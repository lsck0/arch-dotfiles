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
        end,
    },

    {
        "MagicDuck/grug-far.nvim", -- fast project-wide search/replace, live preview
        cmd = "GrugFar",
        opts = {},
    },

    {
        "dont-be-evil-company/kulala.nvim", -- REST client
        -- last pure-lua + curl release: the next commit moved requests to a kulala-core binary whose repo is gone,
        -- later ones fetch it from core.kulala.app behind a license token prompt
        tag = "v5.3.4",
        -- its only submodule is kulala-fmt (system package here, conform runs it), and checking it out from a newer
        -- clone fails; costs only the import/convert-to-http action, which npm-builds that submodule
        submodules = false,
        ft = { "http", "rest" },
        -- the global ones, so they load kulala from any buffer
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
            -- its bundled kulala_http parser installs through nvim-treesitter (tree-sitter-cli in programming/packages.txt)
        },
    },

    {
        "jiaoshijie/undotree", -- undo history tree
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
            vim.keymap.set(
                { "n", "v" },
                "<leader>E",
                require("nvim-emmet").wrap_with_abbreviation,
                { desc = "Emmet wrap with abbreviation" }
            )
        end,
    },
}
