-- latexindent/chktex configs: configs/formatting, .latexmkrc: configs/latex
return {
    {
        "jbyuki/nabla.nvim", -- inline math preview
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
            -- engine and bib come from ~/.latexmkrc
            vim.g.vimtex_compiler_method = "latexmk"
            vim.g.vimtex_compiler_latexmk = {
                options = {
                    "-verbose",
                    "-file-line-error",
                    "-synctex=1",
                    "-interaction=nonstopmode",
                },
            }

            -- zathura_simple: the xdotool window lookup fails on wayland
            vim.g.vimtex_view_method = "zathura_simple"
            -- off: spawning the viewer on open lagged the buffer for seconds
            vim.g.vimtex_view_forward_search_on_start = false

            vim.g.vimtex_fold_enabled = 1
            vim.g.vimtex_toc_config = {
                name = "TOC",
                layers = { "content", "todo", "include" },
                split_width = 30,
                show_help = 0,
            }
            vim.g.tex_conceal = "abdmg"

            -- open quickfix on errors only, without stealing the cursor
            vim.g.vimtex_quickfix_mode = 2
            vim.g.vimtex_quickfix_open_on_warning = 0
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
                    vim.opt_local.spelllang = "en"
                    vim.opt_local.wrap = true
                end,
            })
        end,
    },
}
