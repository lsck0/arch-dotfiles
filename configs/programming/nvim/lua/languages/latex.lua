-- latexindent/chktex configs: configs/programming/formatting, .latexmkrc: configs/latex/latex
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

            -- not vimtex's sioyek: its --inverse-search swaps prefs_user.config's synctex-edit for a headless nvim without ft-lazy vimtex
            -- the running sioyek reuses the window showing the pdf (configs/latex/sioyek), --nofocus keeps the cursor in nvim
            vim.g.vimtex_view_method = "general"
            vim.g.vimtex_view_general_viewer = "sioyek"
            vim.g.vimtex_view_general_options = "--nofocus --forward-search-file @tex --forward-search-line @line @pdf"
            -- the compile-success autocmd below opens the viewer, a second opener would race it into two windows
            vim.g.vimtex_view_automatic = 0

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
                    vim.opt_local.wrap = true
                end,
            })

            -- pywal maps Todo near the background, so vimtex's texCmdTodo (\todo and friends) renders invisible; force a loud marker that survives theme reloads
            local function draft_markers()
                vim.api.nvim_set_hl(0, "texCmdTodo", { link = "DiagnosticWarn", bold = true })
            end
            vim.api.nvim_create_autocmd("ColorScheme", { callback = draft_markers })
            draft_markers()

            -- reload sources the paper repo's .latexmkrc stamped ids into; scheduled, checktime in the autocmd never reloads
            vim.api.nvim_create_autocmd("User", {
                pattern = { "VimtexEventCompileSuccess", "VimtexEventCompileFailed" },
                callback = function(args)
                    vim.schedule(function()
                        if vim.fn.getcmdwintype() == "" then vim.cmd.checktime() end
                        -- forward search after every build, so the pdf follows the line just edited
                        if args.match == "VimtexEventCompileSuccess" and vim.b.vimtex then vim.cmd.VimtexView() end
                    end)
                end,
            })
        end,
    },
}
