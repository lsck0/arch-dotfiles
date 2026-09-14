return {
    { "nvim-tree/nvim-web-devicons" }, -- filetype icons

    {
        url = "https://github.com/AlphaTechnolog/pywal.nvim.git",
        name = "pywal",
        config = function()
            require("pywal").setup()
        end,
    },

    {
        "xiyaowong/transparent.nvim", -- transparent editor surfaces
        dependencies = { "pywal" },
        config = function()
            require("transparent").setup({
                extra_groups = {
                    "NormalFloat",
                    "NvimTreeNormal",
                    "NeoTreeNormal",
                    "TelescopeNormal",
                    "WhichKeyFloat",
                    "BufferTabpageFill",
                    "BufferOffset",
                    "TabLine",
                    "TabLineFill",
                    "StatusLine",
                    "StatusLineNC",
                    "BufferCurrent",
                    "BufferCurrentIndex",
                    "BufferCurrentMod",
                    "BufferCurrentSign",
                    "BufferVisible",
                    "BufferVisibleIndex",
                    "BufferVisibleMod",
                    "BufferVisibleSign",
                    "BufferInactive",
                    "BufferInactiveIndex",
                    "BufferInactiveMod",
                    "BufferInactiveSign",
                },
                exclude_groups = {},
            })

            -- pywal owns the foreground palette; transparent.nvim only removes
            -- panel backgrounds, leaving tab text and accents readable.
            vim.api.nvim_create_autocmd("ColorScheme", {
                callback = function()
                    vim.schedule(function()
                        require("transparent").clear()
                    end)
                end,
            })
            require("transparent").clear()
        end,
    },

    -- Real colorscheme plugins, applied by themes.lua.
    { "folke/tokyonight.nvim",      lazy = true },
    { "Shatur/neovim-ayu",          lazy = true },
    {
        "catppuccin/nvim",
        name = "catppuccin",
        lazy = true,
        config = function()
            require("catppuccin").setup({
                flavour = "mocha",
                transparent_background = false,
                term_colors = true,
                integrations = {
                    barbar = true,
                    dadbod_ui = true,
                    diffview = true,
                    fidget = true,
                    harpoon = true,
                    leap = true,
                    lsp_trouble = true,
                    mason = true,
                    noice = true,
                    notify = true,
                    snacks = { enabled = true },
                },
            })
        end
    },
    { "shaunsingh/nord.nvim",     lazy = true },
    { "ellisonleao/gruvbox.nvim", lazy = true },
    { "oxfist/night-owl.nvim",    lazy = true },
    { "Mofiqul/dracula.nvim",     lazy = true },
    { "navarasu/onedark.nvim",    lazy = true },

    { "romgrk/barbar.nvim" }, -- buffer tabline

    {
        "nvim-lualine/lualine.nvim", -- statusline
        dependencies = { "xiyaowong/transparent.nvim" },
        config = function()
            require("lualine").setup({
                options = {
                    theme = "auto",
                    globalstatus = true,

                    section_separators = { left = "", right = "" },
                    component_separators = { left = "", right = "" },
                },
                sections = {
                    lualine_a = { "mode" },
                    lualine_b = { "branch", "diff", "diagnostics" },
                    lualine_c = { { "filename", path = 1 } },
                    lualine_x = {
                        -- active LSP name hidden (issue 10)
                        "filetype",
                    },
                    lualine_y = {},
                    lualine_z = { "location" },
                },
            })
            -- Transparent statusline: clear the b/c/x/y lualine_* highlight
            -- groups' bg to NONE, same as every other panel transparent.nvim
            -- already handles. `clear_prefix` (not a hardcoded group list)
            -- also covers the per-diagnostic/per-diff groups lualine
            -- generates lazily (lualine_b_diagnostics_error_normal etc — 60+
            -- groups, not just the dozen visible in a plain setup), and
            -- registers each prefix so transparent.nvim's own ColorScheme
            -- re-clear (see ui.lua's transparent.nvim autocmd) keeps
            -- catching new ones on every theme switch, not just this one.
            --
            -- Deliberately EXCLUDES "lualine_a": the mode indicator (section
            -- a) and the far-right location component (section z reuses
            -- section a's highlight groups verbatim, see lualine's
            -- highlight.lua section_highlight_map z -> a) both depend on a
            -- solid, mode-colored background to be legible. Clearing it left
            -- both rendering as blank gaps (foreground-only text in a color
            -- indistinguishable from the transparent bg behind it).
            for _, prefix in ipairs({ "lualine_b", "lualine_c", "lualine_x", "lualine_y" }) do
                require("transparent").clear_prefix(prefix)
            end
        end
    },

    {
        "xiyaowong/virtcolumn.nvim", -- virtual colorcolumn
        config = function()
            vim.g.virtcolumn_char = "▕"
            vim.g.virtcolumn_priority = 10
        end
    },

    {
        "lukas-reineke/indent-blankline.nvim", -- indent guides
        main = "ibl",
        dependencies = {
            { "HiPhish/rainbow-delimiters.nvim" }, -- rainbow bracket colors
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
        "NvChad/nvim-colorizer.lua", -- inline color previews
        event = "VeryLazy",
        config = function()
            require("colorizer").setup({
                user_default_options = {
                    mode = "virtualtext",
                    virtualtext_inline = true,
                    tailwind = true,
                    always_update = true,
                    suppress_deprecation = true,
                },
            })
        end
    },

    {
        "folke/snacks.nvim", -- QoL utility bundle
        opts = {
            bigfile = { enabled = true },
            dashboard = {
                enabled = false,
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
                doc = {
                    -- Cap rendered diagram/image size (was full-window huge
                    -- for wide mermaid blocks)
                    max_width = 60,
                    max_height = 24,
                },
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
                        packages = { "tikz-cd", "/home/luca/projects/paper/template/header" },
                    }
                }
            },
            notifier = { enabled = true },
        },
    },

    {
        "folke/noice.nvim",         -- UI for messages/cmdline
        dependencies = {
            "MunifTanjim/nui.nvim", -- UI component library
            "rcarriga/nvim-notify", -- notification popups
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
        "folke/trouble.nvim", -- diagnostics/quickfix list
        config = function()
            require("trouble").setup()
        end
    },

    {
        "yorickpeterse/nvim-pqf", -- pretty quickfix list
        config = function() require("pqf").setup() end
    },
}
