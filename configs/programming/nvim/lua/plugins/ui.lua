local LATEX_IMAGES = [[
(displayed_equation (#set! image.ext "math.tex")) @image.content @image

((math_environment (#set! image.ext "math.tex")) @image.content @image
  (#not-has-ancestor? @image "displayed_equation" "math_environment"))

(graphics_include (_ (path) @image.src)) @image
]]

-- the density math pdfs rasterize at; snacks reads a png's size as pixels / dpi * 96 * terminal scale
local MATH_DPI = 192

-- Pads a formula to whole cells: snacks rounds width and height up to cells apart and the terminal stretches the image
-- into that box, so a formula 1.2 rows tall came out 2 rows tall.
local function math_args()
    local term = Snacks.image.terminal.size()
    local plain = { "-density", MATH_DPI, "{src}[{page}]", "-trim" }
    -- a terminal that reports no pixel size gives 0-wide cells
    if term.cell_width <= 0 or term.cell_height <= 0 then
        return plain
    end
    local k = MATH_DPI / (96 * term.scale)
    local w, h = term.cell_width * k, term.cell_height * k
    local extent = ("%%[fx:floor(ceil(w/%f)*%f)]x%%[fx:floor(ceil(h/%f)*%f)]"):format(w, w, h, h)
    return {
        "-density",
        MATH_DPI,
        "{src}[{page}]",
        "-trim",
        "+repage",
        "-background",
        "none",
        "-gravity",
        "center",
        "-extent",
        extent,
    }
end

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
                        math = math_args,
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
                -- display math ($$...$$, environments) renders through tectonic or pdflatex; LATEX_IMAGES leaves
                -- inline math as source
                math = { enabled = true, latex = { font_size = "normalsize" } },
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
            -- snacks' latex images minus inline_formula: an inline image fills whole cells, so a one-letter formula
            -- stretches to the row height. Set, not an after/queries file: the first non-extending file in rtp wins.
            vim.treesitter.query.set("latex", "images", LATEX_IMAGES)
            -- the explorer's close forgets only the closed folder's listing: an expanded subfolder keeps its cache and,
            -- under a closed parent, loses its watch, so a file a tool writes there stays hidden after reopening.
            -- Closing forgets the whole subtree, and reopening rescans it.
            local Tree = require("snacks.explorer.tree")
            local tree_close = Tree.close
            function Tree:close(path)
                tree_close(self, path)
                local node = self:find(self:dir(path))
                if node then
                    self:walk(node, function(n)
                        n.expanded = false
                    end, { all = true })
                end
            end
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
