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
        init = function()
            vim.g.transparent_enabled = true
        end,
        config = function()
            require("transparent").setup({
                extra_groups = {
                    "NormalFloat",
                    "NeoTreeNormal",
                    "NeoTreeNormalNC",
                    "NvimTreeNormal",
                    "NvimTreeNormalNC",
                    "TelescopeNormal",
                    "WhichKeyFloat",
                    "BufferTabpageFill",
                    "BufferOffset",
                    "TabLine",
                    "TabLineFill",
                    "StatusLine",
                    "StatusLineNC",
                    "VertSplit",
                    "WinSeparator",
                    "SignColumn",
                    "EndOfBuffer",
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

            -- pywal owns the foreground palette; transparent.nvim only removes panel backgrounds, leaving tab text and accents readable.
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

    { "romgrk/barbar.nvim", event = "VeryLazy" }, -- buffer tabline

    {
        "nvim-lualine/lualine.nvim", -- statusline
        event = "VeryLazy",
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
                    -- dropbar breadcrumbs (path + symbols) rendered at the bottom via lualine.
                    lualine_c = { { function() return "%{%v:lua.dropbar()%}" end } },
                    lualine_x = {
                        -- active LSP name hidden (issue 10)
                        "filetype",
                    },
                    lualine_y = {},
                    lualine_z = { "location" },
                },
            })
            for _, prefix in ipairs({ "lualine_b", "lualine_c", "lualine_x", "lualine_y" }) do
                require("transparent").clear_prefix(prefix)
            end
        end
    },

    {
        "xiyaowong/virtcolumn.nvim", -- virtual colorcolumn
        event = "VeryLazy",
        config = function()
            vim.g.virtcolumn_char = "▕"
            vim.g.virtcolumn_priority = 10
        end
    },

    {
        "HiPhish/rainbow-delimiters.nvim", -- rainbow bracket colors (indent guides now via snacks.indent)
        event = { "BufReadPost", "BufNewFile" },
        config = function()
            local highlight = {
                "RainbowRed", "RainbowYellow", "RainbowBlue", "RainbowOrange",
                "RainbowGreen", "RainbowViolet", "RainbowCyan",
            }
            vim.api.nvim_set_hl(0, "RainbowRed", { fg = "#E06C75" })
            vim.api.nvim_set_hl(0, "RainbowYellow", { fg = "#E5C07B" })
            vim.api.nvim_set_hl(0, "RainbowBlue", { fg = "#61AFEF" })
            vim.api.nvim_set_hl(0, "RainbowOrange", { fg = "#D19A66" })
            vim.api.nvim_set_hl(0, "RainbowGreen", { fg = "#98C379" })
            vim.api.nvim_set_hl(0, "RainbowViolet", { fg = "#C678DD" })
            vim.api.nvim_set_hl(0, "RainbowCyan", { fg = "#56B6C2" })
            vim.g.rainbow_delimiters = { highlight = highlight }
        end
    },

    {
        "NvChad/nvim-colorizer.lua", -- inline color previews
        event = "VeryLazy",
        config = function()
            -- Named colors (black/red/...) and tailwind matches turn any
            require("colorizer").setup({
                user_default_options = {
                    mode = "virtualtext",
                    virtualtext_inline = true,
                    names = false,
                    tailwind = false,
                    always_update = true,
                    suppress_deprecation = true,
                },
                filetypes = {
                    "*",
                    css = { names = true, tailwind = true },
                    scss = { names = true, tailwind = true },
                    sass = { names = true, tailwind = true },
                    less = { names = true, tailwind = true },
                    html = { names = true, tailwind = true },
                    javascriptreact = { tailwind = true },
                    typescriptreact = { tailwind = true },
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
            -- noice + nvim-notify already handle notifications; don't double up
            notifier = { enabled = false },
            indent = { enabled = true }, -- indent guides + scope (replaces indent-blankline)
            scroll = { enabled = false }, -- no smooth scrolling
            words = { enabled = true },  -- highlight LSP references under cursor (replaces mini.cursorword)
            -- File browser (snacks, in place of neo-tree), pinned to the git root.
            explorer = { replace_netrw = true },
            picker = {
                sources = {
                    explorer = {
                        follow_file = false,
                        hidden = true, -- show dotfiles on start
                        auto_close = false,
                        jump = { close = false },
                        -- custom layout: list window only, no input/title box
                        layout = {
                            preview = false,
                            layout = {
                                box = "vertical",
                                position = "left",
                                width = 24,
                                min_width = 24,
                                height = 0,
                                border = "none",
                                { win = "list", border = "none" },
                            },
                        },
                    },
                },
            },
        },
        config = function(_, opts)
            require("snacks").setup(opts)
            -- Diagrams only in normal mode: snacks re-evaluates image visibility on every ModeChanged, so hide them all in insert.
            local inline = require("snacks.image.inline")
            local conceal = inline.conceal
            function inline:conceal()
                conceal(self)
                if vim.fn.mode():sub(1, 1) == "i" then
                    for _, img in pairs(self.imgs) do
                        img:hide()
                    end
                end
            end
        end,
    },

    {
        "folke/noice.nvim",         -- UI for messages/cmdline
        event = "VeryLazy",
        dependencies = {
            "MunifTanjim/nui.nvim", -- UI component library
            {
                "rcarriga/nvim-notify", -- notification popups
                -- transparent.nvim strips NotifyBackground, so set an explicit background_colour.
                opts = { background_colour = "#000000", render = "compact" },
            },
        },
        config = function()
            require("noice").setup({
                presets = {
                    command_palette = true,
                    long_message_to_split = true,
                },
                messages = { enabled = true },
                cmdline = { enabled = true },
                -- don't pop up for trivial edits (yank/delete/paste line counts).
                routes = {
                    { filter = { event = "msg_show", kind = "search_count" }, opts = { skip = true } },
                    { filter = { event = "msg_show", find = "%d+ lines yanked" }, opts = { skip = true } },
                    { filter = { event = "msg_show", find = "%d+ fewer lines" }, opts = { skip = true } },
                    { filter = { event = "msg_show", find = "%d+ more lines" }, opts = { skip = true } },
                    { filter = { event = "msg_show", find = "%d+ lines changed" }, opts = { skip = true } },
                    { filter = { event = "msg_show", find = "%d+ lines >ed %d+ time" }, opts = { skip = true } },
                    { filter = { event = "msg_show", find = "%d+ lines <ed %d+ time" }, opts = { skip = true } },
                    { filter = { event = "msg_show", find = "%d+L, %d+B" }, opts = { skip = true } },
                    { filter = { event = "msg_show", find = "written" }, opts = { skip = true } },
                    { filter = { event = "msg_show", find = "-- INSERT --" }, opts = { skip = true } },
                    { filter = { event = "notify", find = "deprecated" }, opts = { skip = true } },
                    { filter = { find = "buf_get_clients" }, opts = { skip = true } },
                },
            })
        end
    },

    {
        "folke/trouble.nvim", -- diagnostics/quickfix list
        cmd = "Trouble",
        config = function()
            require("trouble").setup()
        end
    },

    {
        "yorickpeterse/nvim-pqf", -- pretty quickfix list
        event = "VeryLazy",
        config = function() require("pqf").setup() end
    },
}
