return {
    {
        "ej-shafran/compile-mode.nvim",
        branch = "latest",
        dependencies = {
            { "m00qek/baleia.nvim", tag = "v1.3.0" },
        },
        config = function()
            vim.g.compile_mode = {
                baleia_setup = true,
            }
        end
    },

    {
        "nvim-pack/nvim-spectre",
        config = function()
            require('spectre').setup()
        end
    },

    {
        "mistweaverco/kulala.nvim",
        lazy = false,
        keys = {
            { "<leader>rs", desc = "Send request" },
            { "<leader>ra", desc = "Send all requests" },
            { "<leader>rb", desc = "Open scratchpad" },
        },
        ft = { "http", "rest" },
        opts = {
            global_keymaps = true,
            global_keymaps_prefix = "<leader>r",
            kulala_keymaps_prefix = "",
        },
    },

    {
        "jiaoshijie/undotree",
        lazy = false,
        dependencies = "nvim-lua/plenary.nvim",
        config = true,
        keys = {
            { "<leader>u", "<cmd>lua require('undotree').toggle()<cr>" },
        },
    },

    {
        "piersolenski/import.nvim",
        lazy = false,
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
        'Julian/lean.nvim',
        dependencies = {
            { 'neovim/nvim-lspconfig' },
            { 'nvim-lua/plenary.nvim' },
        },
        opts = {
            mappings = true,
        }
    },

    {
        "epwalsh/pomo.nvim",
        version = "*",
        lazy = true,
        cmd = { "TimerStart", "TimerRepeat", "TimerSession" },
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

    { "sotte/presenting.nvim" },
}
