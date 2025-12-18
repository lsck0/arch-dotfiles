local installed = {
    "bash-language-server",
    "bibtex-tidy",
    "black",
    "clangd",
    "codelldb",
    "css-lsp",
    "cssmodules-language-server",
    "docker_compose_language_service",
    "dockerfile-language-server",
    "emmet_language_server",
    "eslint-lsp",
    "glsl_analyzer",
    "gopls",
    "hlint",
    "html-lsp",
    "isort",
    "jinja-lsp",
    "json-lsp",
    "latexindent",
    "lean-language-server",
    "lua-language-server",
    "nil",
    "prettierd",
    "pyright",
    "rust_analyzer",
    "sqlls",
    "tailwindcss-language-server",
    "taplo",
    "terraform-ls",
    "texlab",
    "tree-sitter-cli",
    "typescript-language-server",
    "typos_lsp",
    "vim-language-server",
    "yaml-language-server",
    "zls",
}

return {
    {
        "mason-org/mason.nvim",
        dependencies = {
            { "jay-babu/mason-null-ls.nvim" },
            { "neovim/nvim-lspconfig" },
            { "nvimtools/none-ls.nvim" },
            { "mason-org/mason-lspconfig.nvim" },
            {
                "ivanjermakov/troublesum.nvim",
                config = function()
                    require("troublesum").setup()
                end
            },
            {
                "MysticalDevil/inlay-hints.nvim",
                dependencies = { "neovim/nvim-lspconfig" },
                config = function()
                    require("inlay-hints").setup()
                end
            },
            {
                "Sebastian-Nielsen/better-type-hover",
                config = function()
                    require("better-type-hover").setup()
                end,
            },
            {
                "folke/lazydev.nvim",
                ft = "lua",
                opts = {
                    library = {
                        { path = "${3rd}/luv/library", words = { "vim%.uv" } },
                    },
                },
            },
            {
                "dmmulroy/ts-error-translator.nvim",
                config = function()
                    require("ts-error-translator").setup()
                end
            },
            { "rluba/jai.vim" },
            { "lervag/vimtex" },
            {
                "saecki/crates.nvim",
                config = function()
                    require("crates").setup({})
                end
            },
        },
        config = function()
            vim.diagnostic.config({ virtual_text = true })

            require("mason").setup()
            require("null-ls").setup()
            require("mason-null-ls").setup({
                ensure_installed = installed,
                handlers = {},
                automatic_installation = true,
            })

            vim.lsp.config("rust_analyzer", {
                settings = {
                    ["rust-analyzer"] = {
                        check = {
                            command = "clippy",
                        }
                    }
                }
            })
            vim.lsp.enable("rust_analyzer")

            vim.lsp.config("clangd", {
                cmd = {
                    "clangd",
                    "--offset-encoding=utf-16",
                    "--background-index",
                    "--suggest-missing-includes",
                },
            })
            vim.lsp.enable("clangd")

            require("mason-lspconfig").setup({
                automatic_enable = {
                    exclude = {
                        "clangd",
                        "rust_analyzer",
                    }
                }
            })
        end,
    },

    {
        "stevearc/conform.nvim",
        config = function()
            require("conform").formatters.sortderives = {
                inherit = false,
                command = "/usr/local/bin/sort-derives-stdout",
                stdin = true,
            }

            require("conform").setup({
                formatters_by_ft = {
                    bib = { "bibtex-tidy" },
                    css = { "prettier" },
                    html = { "prettier" },
                    javascript = { "prettier" },
                    latex = { "latexindent" },
                    python = { "isort", "black" },
                    rust = { "rustfmt", "sortderives" },
                    scss = { "prettier" },
                },
                format_on_save = {
                    timeout_ms = 1000,
                    lsp_format = "fallback",
                },
            })
        end,
    }
}
