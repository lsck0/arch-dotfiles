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

    -- Real colorscheme plugins, one per handwritten theme. The themes are
    -- applied by pick-a-theme-wallpaper (switch-wallpaper.sh writes the
    -- theme's own name to ~/.cache/wal/nvim_theme, which lua/theme.lua +
    -- lua/themes/<name>.lua dispatch to the right :colorscheme). These
    -- render each theme's actual semantic syntax colors; pywal.nvim (above)
    -- stays as the fallback for photo wallpapers.
    --
    -- lazy = true with NO cmd/event/ft trigger: each lua/themes/<name>.lua
    -- file explicitly calls require("lazy.core.loader").load("<plugin>")
    -- itself before switching, so nothing here needs to guess which trigger
    -- fires it. `cmd = "colorscheme"` was tried first and is NOT valid —
    -- lazy.nvim's cmd handler creates a real user command with that exact
    -- name via nvim_create_user_command, which nvim rejects unless it starts
    -- with an uppercase letter ("Invalid command name (must start with
    -- uppercase): 'colorscheme'"), crashing startup for every cmd="colorscheme"
    -- plugin.
    { "folke/tokyonight.nvim",   lazy = true },
    { "Shatur/neovim-ayu",       lazy = true },
    { "catppuccin/nvim",         name = "catppuccin", lazy = true,
      config = function()
        require("catppuccin").setup({
          flavour = "mocha", transparent_background = false, term_colors = true,
          integrations = {
            barbar = true, dadbod_ui = true, diffview = true, fidget = true,
            harpoon = true, leap = true, lsp_trouble = true, mason = true,
            noice = true, notify = true, snacks = { enabled = true },
          },
        })
      end },
    { "shaunsingh/nord.nvim",    lazy = true },
    { "ellisonleao/gruvbox.nvim", lazy = true },
    { "oxfist/night-owl.nvim",   lazy = true },
    { "Mofiqul/dracula.nvim",    lazy = true },
    { "navarasu/onedark.nvim",   lazy = true },

    { "romgrk/barbar.nvim" }, -- buffer tabline

    {
        "nvim-lualine/lualine.nvim", -- statusline
        config = function()
            local pomo_timer = {
                function()
                    -- package.loaded check (not require) so this doesn't force
                    -- pomo.nvim to load on every statusline redraw before any
                    -- :TimerStart has ever run — see feat.lua's cmd= trigger
                    if not package.loaded["pomo"] then return "" end
                    local timer = require("pomo").get_first_to_finish()
                    if timer == nil then return "" end
                    return "󰔟 " .. tostring(timer)
                end,
            }

            require("lualine").setup({
                options = {
                    -- "auto", not "pywal": lualine's auto theme reads
                    -- vim.g.colors_name (set by whichever :colorscheme
                    -- actually ran — see lua/theme.lua) and loads the
                    -- matching bundled statusline theme when one exists
                    -- (ayu_dark, gruvbox, dracula, nord, onedark all ship
                    -- with lualine); otherwise it derives colors live from
                    -- the active highlight groups. Pinning to "pywal" meant
                    -- every handwritten theme's syntax colors were correct
                    -- but the statusline stayed on pywal's flat palette —
                    -- the mismatch that made e.g. ayu look "massively
                    -- different" from ayu.nvim's own statusline.
                    theme = "auto",
                    globalstatus = true,
                    component_separators = { left = "", right = "" },
                    section_separators = { left = "", right = "" },
                },
                sections = {
                    lualine_a = { "mode" },
                    lualine_b = { "branch", "diff", "diagnostics" },
                    lualine_c = { { "filename", path = 1 } },
                    lualine_x = {
                        pomo_timer,
                        { "lsp_status", icon = "" },
                        "filetype",
                    },
                    lualine_y = {},
                    lualine_z = { "location" },
                },
            })
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
        -- TODO.md perf-audit note also suggests scoping `ft` to filetypes
        -- that actually carry color literals — left alone here since that
        -- changes behavior (what gets colorized), not just load timing,
        -- and is a real preference call rather than a pure perf fix
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
