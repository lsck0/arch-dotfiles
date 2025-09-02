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
        'kristijanhusak/vim-dadbod-ui',
        dependencies = {
            { 'tpope/vim-dadbod',                     lazy = true },
            { 'kristijanhusak/vim-dadbod-completion', ft = { 'sql', 'mysql', 'plsql' }, lazy = true },
        },
        cmd = {
            'DBUI',
            'DBUIToggle',
            'DBUIAddConnection',
            'DBUIFindBuffer',
        },
        init = function()
            vim.g.db_ui_use_nerd_fonts = 1
        end,
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
        "laytan/cloak.nvim",
        config = function()
            require("cloak").setup({
                enabled = true,
                cloak_character =
                "#",
                highlight_group = "Comment",
                patterns = { { file_pattern = { "*.env*" }, cloak_pattern = "=.+" }, },
            })
        end
    },

    {
        "MeanderingProgrammer/render-markdown.nvim",
        dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" },
        config = function()
            require("render-markdown").enable()
            require("render-markdown").setup({
                completions = { lsp = { enabled = true } },
            })
        end
    },

    {
        "echasnovski/mini.nvim",
        config = function()
            require("mini.ai").setup()
            require("mini.align").setup()
            require("mini.move").setup()
            require("mini.jump").setup()
            require('mini.cursorword').setup()
            require("mini.pairs").setup()
            require("mini.splitjoin").setup()
            require("mini.surround").setup({
                mappings = {
                    add = "ea",
                    delete = "ed",
                    replace = "er",
                    find = "ef",
                    find_left = "eF",
                    highlight = "eh",
                    update_n_lines = "en",
                }
            })
        end
    },

    {
        "nvim-neorg/neorg",
        version = "*",
        config = function()
            require('neorg').setup({
                load = {
                    ["core.defaults"] = {},
                    ["core.concealer"] = {},
                    ["core.completion"] = {
                        config = {
                            engine = "nvim-cmp",
                        }
                    }
                },
            })
        end
    },

    {
        'piersolenski/import.nvim',
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
}
