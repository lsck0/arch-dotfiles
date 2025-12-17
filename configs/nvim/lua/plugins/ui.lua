return {
    { "nvim-tree/nvim-web-devicons" },

    {
        url = "https://github.com/AlphaTechnolog/pywal.nvim.git",
        priority = 1000,
        name = "pywal",
        config = function()
            require('pywal').setup()
        end,
    },

    -- {
    --     "catppuccin/nvim",
    --     priority = 1000,
    --     name = "catppuccin",
    --     config = function()
    --         require("catppuccin").setup({
    --             flavour = "mocha",
    --             transparent_background = false,
    --             term_colors = true,
    --             integrations = {
    --                 barbar = true,
    --                 dadbod_ui = true,
    --                 diffview = true,
    --                 fidget = true,
    --                 harpoon = true,
    --                 leap = true,
    --                 lsp_trouble = true,
    --                 mason = true,
    --                 noice = true,
    --                 notify = true,
    --                 snacks = { enabled = true, },
    --             },
    --         })
    --         vim.cmd.colorscheme "catppuccin"
    --     end
    -- },

    -- {
    --     "EdenEast/nightfox.nvim",
    --     priority = 1000,
    --     config = function()
    --         vim.cmd.colorscheme "carbonfox"
    --     end
    -- },

    { "romgrk/barbar.nvim" },

    {
        "nvim-lualine/lualine.nvim",
        config = function()
            require("lualine").setup({
                options = {
                    -- theme = "carbonfox",
                    -- theme = "catppuccin",
                    theme = "pywal-nvim",
                },
                sections = {
                    lualine_x = {
                        {
                            function()
                                local ok, pomo = pcall(require, "pomo")
                                if not ok then
                                    return ""
                                end

                                local timer = pomo.get_first_to_finish()
                                if timer == nil then
                                    return ""
                                end

                                return tostring(timer)
                            end,
                        }
                    },
                },
            })
        end
    },


    {
        "xiyaowong/virtcolumn.nvim",
        config = function()
            vim.g.virtcolumn_char = "▕"
            vim.g.virtcolumn_priority = 10
        end
    },

    {
        "lukas-reineke/indent-blankline.nvim",
        main = "ibl",
        dependencies = {
            { "HiPhish/rainbow-delimiters.nvim" },
        },
        config = function()
            local highlight = {
                "RainbowRed",
                "RainbowYellow",
                "RainbowBlue",
                "RainbowOrange",
                "RainbowGreen",
                "RainbowViolet",
                "RainbowCyan",
            }
            local hooks = require "ibl.hooks"
            hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
                vim.api.nvim_set_hl(0, "RainbowRed", { fg = "#E06C75" })
                vim.api.nvim_set_hl(0, "RainbowYellow", { fg = "#E5C07B" })
                vim.api.nvim_set_hl(0, "RainbowBlue", { fg = "#61AFEF" })
                vim.api.nvim_set_hl(0, "RainbowOrange", { fg = "#D19A66" })
                vim.api.nvim_set_hl(0, "RainbowGreen", { fg = "#98C379" })
                vim.api.nvim_set_hl(0, "RainbowViolet", { fg = "#C678DD" })
                vim.api.nvim_set_hl(0, "RainbowCyan", { fg = "#56B6C2" })
            end)

            vim.g.rainbow_delimiters = { highlight = highlight }
            require("ibl").setup { scope = { highlight = highlight } }

            hooks.register(hooks.type.SCOPE_HIGHLIGHT, hooks.builtin.scope_highlight_from_extmark)
        end
    },

    {
        "NvChad/nvim-colorizer.lua",
        lazy = false,
        event = "BufRead",
        config = function()
            require("colorizer").setup({
                user_default_options = {
                    mode = "virtualtext",
                    virtualtext_inline = true,
                    tailwind = true,
                    always_update = true,
                },
            })
        end
    },

    {
        "folke/snacks.nvim",
        opts = {
            bigfile = { enabled = true },
            dashboard = {
                enabled = true,
                preset = {
                    keys = {
                        { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
                        { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
                        { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
                        { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
                        { icon = "󰒲 ", key = "L", desc = "Lazy", action = ":Lazy", enabled = package.loaded.lazy ~= nil },
                        { icon = " ", key = "q", desc = "Quit", action = ":qa" },
                    },
                }
            },
            image = {
                enabled = true,
                convert = {
                    magick = {
                        pdf = {
                            "-density", 192, "{src}[0]", "-background", "white", "-alpha", "remove", -- "-trim"
                        },
                    }
                },
                math = {
                    enabled = false,
                    latex = {
                        font_size = "Large",
                        packages = { "tikz-cd", "/home/luca/code/paper/template/header" },
                    }
                }
            },
            notifier = { enabled = true },
        },
    },

    {
        "folke/noice.nvim",
        dependencies = {
            "MunifTanjim/nui.nvim",
            "rcarriga/nvim-notify",
        },
        config = function()
            require("noice").setup({
                presets = {
                    command_palette = true,
                    long_message_to_split = true,
                },
                messages = { enabled = true },
                cmdline = { enabled = true },
            })
        end
    },

    {
        "folke/trouble.nvim",
        config = function()
            require("trouble").setup()
        end
    },

    {
        "yorickpeterse/nvim-pqf",
        config = function() require("pqf").setup() end
    },
}
