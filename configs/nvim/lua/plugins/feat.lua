return {
    {
        "ej-shafran/compile-mode.nvim", -- Emacs-style compile mode
        branch = "latest",
        dependencies = {
            { "m00qek/baleia.nvim", tag = "v1.3.0" }, -- ANSI color rendering
        },
        config = function()
            vim.g.compile_mode = {
                baleia_setup = true,
            }
        end
    },

    {
        "nvim-pack/nvim-spectre", -- project search and replace
        config = function()
            require('spectre').setup()
        end
    },

    {
        "mistweaverco/kulala.nvim", -- REST client
        ft = { "http", "rest" },
        opts = {
            global_keymaps = true,
            global_keymaps_prefix = "<leader>r",
            kulala_keymaps_prefix = "",
        },
    },

    {
        "jiaoshijie/undotree", -- undo history tree
        dependencies = "nvim-lua/plenary.nvim", -- Lua utility library
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
        'Julian/lean.nvim', -- Lean theorem prover
        dependencies = {
            { 'neovim/nvim-lspconfig' }, -- LSP server configs
            { 'nvim-lua/plenary.nvim' }, -- Lua utility library
        },
        init = function()
            vim.g.lean_config = {
                mappings = true,
            }
        end,
        config = function() end,
    },

    {
        "epwalsh/pomo.nvim", -- pomodoro timer
        version = "*",
        cmd = { "TimerStart", "TimerStop", "TimerRepeat", "TimerHide", "TimerShow", "TimerPause", "TimerResume", "TimerSession" },
        opts = {
            update_interval = 1000,
            notifiers = {
                {
                    name = "Default",
                    opts = {
                        sticky = false,
                    },
                },
            },
            sessions = {
                pomodoro = {
                    { name = "Work",        duration = "25m" },
                    { name = "Short Break", duration = "5m" },
                    { name = "Work",        duration = "25m" },
                    { name = "Short Break", duration = "5m" },
                    { name = "Work",        duration = "25m" },
                    { name = "Long Break",  duration = "15m" },
                },
            },
        },
    },

    { "sotte/presenting.nvim" }, -- in-editor presentations

    -- {
    --     "lucastavaresa/headers.nvim",
    --     config = function()
    --         require("headers").setup()
    --     end,
    -- },

    {
        "olrtg/nvim-emmet", -- emmet abbreviations
        config = function()
            vim.keymap.set({ "n", "v" }, "<leader>xe", require("nvim-emmet").wrap_with_abbreviation,
                { desc = "Emmet wrap with abbreviation" })
        end,
    },
}
