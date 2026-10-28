return {
    { "nvim-tree/nvim-web-devicons" },

    {
        url = "https://github.com/AlphaTechnolog/pywal.nvim.git",
        name = "pywal",
        lazy = true, -- loaded by colors/wal.lua
    },

    { "folke/tokyonight.nvim", lazy = true },
    { "Shatur/neovim-ayu", lazy = true },
    {
        "catppuccin/nvim",
        name = "catppuccin",
        lazy = true,
        opts = { term_colors = true },
    },
    { "shaunsingh/nord.nvim", lazy = true },
    { "ellisonleao/gruvbox.nvim", lazy = true },
    { "oxfist/night-owl.nvim", lazy = true },
    { "Mofiqul/dracula.nvim", lazy = true },
    { "navarasu/onedark.nvim", lazy = true },

    { "romgrk/barbar.nvim", event = "VeryLazy" },

    {
        "nvim-lualine/lualine.nvim",
        event = "VeryLazy",
        config = function()
            require("lualine").setup({
                options = {
                    theme = vim.g.neovide and "auto" or "glass",
                    globalstatus = true,
                    refresh = { refresh_time = 250 },

                    section_separators = { left = "", right = "" },
                    component_separators = { left = "", right = "" },
                },
                sections = {
                    lualine_a = { "mode" },
                    lualine_b = { "branch", "diff", "diagnostics" },
                    lualine_c = {
                        {
                            function()
                                return "%{%v:lua.dropbar()%}"
                            end,
                        },
                    },
                    lualine_x = { "filetype" },
                    lualine_y = {},
                    lualine_z = { "location" },
                },
            })
        end,
    },

    {
        "xiyaowong/virtcolumn.nvim",
        event = "VeryLazy",
    },

    {
        "HiPhish/rainbow-delimiters.nvim",
        event = { "BufReadPost", "BufNewFile" },
    },

    {
        "NvChad/nvim-colorizer.lua",
        event = "VeryLazy",
        config = function()
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
        end,
    },

    {
        "folke/snacks.nvim",
        priority = 1000,
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
                            "-density",
                            192,
                            "{src}[0]",
                            "-background",
                            "white",
                            "-alpha",
                            "remove",
                        },
                    },
                },
                math = { enabled = false },
            },
            notifier = { enabled = true },
            indent = { enabled = true },
            scroll = { enabled = false },
            words = { enabled = true },
            -- the VimEnter autocmd is the only opener, else roots stack
            explorer = { replace_netrw = false },
            picker = {
                sources = {
                    explorer = {
                        -- its reveal re-roots at the file, stacking roots; lib/explorer.lua reveals instead
                        follow_file = false,
                        hidden = true,
                        ignored = true, -- still dimmed by the git status
                        -- fd only skipped .git because of --no-ignore, which `ignored` just removed
                        exclude = { "**/.git" },
                        auto_close = false,
                        jump = { close = false },
                        actions = {
                            toggle_hidden_ignored = function(picker)
                                local show = not picker.opts.hidden
                                picker.opts.hidden = show
                                picker.opts.ignored = show
                                picker.list:set_target()
                                picker:find()
                            end,
                        },
                        win = { list = { keys = { ["H"] = "toggle_hidden_ignored" } } },
                        icons = { git = { ignored = "\u{f0209} " } },
                        format = function(item, picker)
                            local ret = require("snacks.picker.format").file(item, picker)
                            local it = item
                            while it and not it.ignored do
                                it = it.parent
                            end
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
        "folke/trouble.nvim",
        cmd = "Trouble",
        opts = {},
    },

    {
        "yorickpeterse/nvim-pqf",
        event = "VeryLazy",
        main = "pqf",
        opts = {},
    },
}
