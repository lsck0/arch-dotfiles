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
            -- opaque in neovide: no wallpaper behind it, a stripped bg renders black
            vim.g.transparent_enabled = vim.g.neovide ~= true
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

            if not vim.g.neovide then
                vim.api.nvim_create_autocmd("ColorScheme", {
                    callback = function()
                        vim.schedule(function()
                            require("transparent").clear()
                        end)
                    end,
                })
                require("transparent").clear()
            end
        end,
    },

    -- colorschemes, applied by lua/theme.lua
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
                    flash = true,
                    harpoon = true,
                    lsp_trouble = true,
                    mason = true,
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
                    refresh = { refresh_time = 250 },

                    section_separators = { left = "", right = "" },
                    component_separators = { left = "", right = "" },
                },
                sections = {
                    lualine_a = { "mode" },
                    lualine_b = { "branch", "diff", "diagnostics" },
                    -- dropbar breadcrumbs
                    lualine_c = { { function() return "%{%v:lua.dropbar()%}" end } },
                    lualine_x = { "filetype" },
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
        "HiPhish/rainbow-delimiters.nvim", -- rainbow bracket colors
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
            -- names/tailwind only in css-like filetypes, else plain words get colored
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
        priority = 1000, -- load before other eager UI plugins (snacks health rec)
        opts = {
            bigfile = { enabled = true },
            dashboard = { enabled = false },
            image = {
                enabled = true,
                doc = {
                    max_width = 60,
                    max_height = 24,
                },
                convert = {
                    magick = {
                        pdf = {
                            "-density", 192, "{src}[0]", "-background", "white", "-alpha", "remove",
                        },
                    }
                },
                math = { enabled = false },
            },
            notifier = { enabled = true },
            indent = { enabled = true }, -- indent guides + scope
            scroll = { enabled = false }, -- no smooth scrolling
            words = { enabled = true },  -- highlight lsp references under cursor
            -- the VimEnter autocmd is the only opener, else roots stack
            explorer = { replace_netrw = false },
            picker = {
                sources = {
                    explorer = {
                        -- off: its reveal reopens with cwd=<file>, stacking a root.
                        -- lib/explorer.lua reveals instead, inside the current root only.
                        follow_file = false,
                        hidden = true, -- show dotfiles on start
                        ignored = true, -- and gitignored files; they are still dimmed by the git status
                        -- fd only skipped .git because of --no-ignore, which `ignored` just removed
                        exclude = { "**/.git" },
                        auto_close = false,
                        jump = { close = false },
                        actions = {
                            -- H hides dotfiles and gitignored files together, or shows both again
                            toggle_hidden_ignored = function(picker)
                                local show = not picker.opts.hidden
                                picker.opts.hidden = show
                                picker.opts.ignored = show
                                picker.list:set_target()
                                picker:find()
                            end,
                        },
                        win = { list = { keys = { ["H"] = "toggle_hidden_ignored" } } },
                        -- right-aligned marks: md-eye_off on dotfiles, git's seti-ignored on gitignored entries
                        icons = { git = { ignored = "\u{e668} " } },
                        format = function(item, picker)
                            local ret = require("snacks.picker.format").file(item, picker)
                            -- ignored wins: no hidden mark on an ignored entry or anything inside an ignored dir
                            local it = item
                            while it and not it.ignored do it = it.parent end
                            if item.hidden and not it then
                                table.insert(ret, {
                                    col = 0,
                                    virt_text = { { "\u{f0209} ", "SnacksPickerPathHidden" }, { " " } },
                                    virt_text_pos = "right_align",
                                    hl_mode = "combine",
                                })
                            end
                            return ret
                        end,
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
            -- hide inline images in insert mode
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
