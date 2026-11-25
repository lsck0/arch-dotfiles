local LATEX_IMAGES = [[
(displayed_equation (#set! image.ext "math.tex")) @image.content @image

((math_environment (#set! image.ext "math.tex")) @image.content @image
  (#not-has-ancestor? @image "displayed_equation" "math_environment"))

(graphics_include (_ (path) @image.src)) @image
]]

-- the density pdfs (documents and math) rasterize at; snacks reads a png's size as pixels / dpi * 96 * terminal scale
local PDF_DPI = 192

-- Pads a formula to whole cells: snacks rounds width and height up to cells apart and the terminal stretches the image
-- into that box, so a formula 1.2 rows tall came out 2 rows tall.
local function math_args()
    local term = Snacks.image.terminal.size()
    local plain = { "-density", PDF_DPI, "{src}[{page}]", "-trim" }
    -- a terminal that reports no pixel size gives 0-wide cells
    if term.cell_width <= 0 or term.cell_height <= 0 then
        return plain
    end
    local k = PDF_DPI / (96 * term.scale)
    local w, h = term.cell_width * k, term.cell_height * k
    local extent = ("%%[fx:floor(ceil(w/%f)*%f)]x%%[fx:floor(ceil(h/%f)*%f)]"):format(w, w, h, h)
    return vim.list_extend(plain, { "+repage", "-background", "none", "-gravity", "center", "-extent", extent })
end

return {
    { "nvim-tree/nvim-web-devicons" },

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

    { "romgrk/barbar.nvim", event = "VeryLazy", opts = { sidebar_filetypes = { ["neo-tree"] = true } } },

    {
        "nvim-lualine/lualine.nvim",
        event = "VeryLazy",
        opts = {
            options = {
                theme = "glass",
                globalstatus = true,
                refresh = { refresh_time = 250 },

                section_separators = { left = "", right = "" },
                component_separators = { left = "::", right = "::" },
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
        },
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
        opts = {
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
        },
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
                            PDF_DPI,
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
        },
        config = function(_, opts)
            require("snacks").setup(opts)
            -- snacks' latex images minus inline_formula: an inline image fills whole cells, so a one-letter formula
            -- stretches to the row height. Set, not an after/queries file: the first non-extending file in rtp wins.
            vim.treesitter.query.set("latex", "images", LATEX_IMAGES)
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
