-- LaTeX. latexindent/chktex configs live in configs/formatting, .latexmkrc in configs/latex.
return {
    {
        "jbyuki/nabla.nvim", -- inline math preview (unicode art, works in the terminal)
        ft = { "tex", "plaintex", "markdown" },
        keys = {
            { "<leader>lp", function() require("nabla").popup() end, desc = "Math preview (popup)" },
            { "<leader>lP", function() require("nabla").toggle_virt() end, desc = "Math inline preview toggle" },
        },
    },
    {
        "lervag/vimtex",
        ft = { "tex", "plaintex" },
        init = function()
            -- build: latexmk; engine + bib come from ~/.latexmkrc (pdflatex default, in-place).
            -- a project wanting lualatex/xelatex or a build dir adds its own .latexmkrc.
            vim.g.vimtex_compiler_method = "latexmk"
            vim.g.vimtex_compiler_latexmk = {
                options = {
                    "-verbose",
                    "-file-line-error",
                    "-synctex=1",
                    "-interaction=nonstopmode",
                },
            }

            -- preview: zathura with synctex forward/inverse search
            vim.g.vimtex_view_method = "zathura"
            vim.g.vimtex_view_forward_search_on_start = true

            -- editing: folding, toc, conceal (needs conceallevel, set per-buffer below)
            vim.g.vimtex_fold_enabled = 1
            vim.g.vimtex_toc_config = {
                name = "TOC",
                layers = { "content", "todo", "include" },
                split_width = 30,
                show_help = 0,
            }
            vim.g.tex_conceal = "abdmg"

            -- quickfix: don't jump on build, and drop noise that isn't actionable
            vim.g.vimtex_quickfix_mode = 0
            vim.g.vimtex_quickfix_ignore_filters = {
                "Underfull",
                "Overfull",
                "specifier changed to",
                "Token not allowed in a PDF string",
            }

            vim.api.nvim_create_autocmd("FileType", {
                pattern = { "tex", "plaintex" },
                callback = function()
                    vim.opt_local.conceallevel = 2
                    vim.opt_local.spell = true
                    vim.opt_local.spelllang = "en_us"
                    vim.opt_local.wrap = true
                end,
            })
        end,
    },
}
