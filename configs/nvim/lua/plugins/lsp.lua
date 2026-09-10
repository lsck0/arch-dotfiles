local installed = {
    "bash-language-server",
    "bibtex-tidy",
    "black",
    "clangd",
    "codelldb",
    "css-lsp",
    "cssmodules-language-server",
    "docker-compose-language-service",
    "dockerfile-language-server",
    "emmet-language-server",
    "eslint-lsp",
    "gopls",
    "hlint",
    "html-lsp",
    "hyprls",
    "isort",
    "java-debug-adapter",
    "java-test",
    "jdtls",
    "jinja-lsp",
    "json-lsp",
    "kulala-fmt",
    "latexindent",
    "lean-language-server",
    "lemminx",
    "lua-language-server",
    "nil",
    "prettierd",
    "pyright",
    "rust-analyzer",
    "slang-server",
    "sqlls",
    "tailwindcss-language-server",
    "taplo",
    "terraform-ls",
    "texlab",
    "tree-sitter-cli",
    "typescript-language-server",
    "typos-lsp",
    "vim-language-server",
    "yaml-language-server",
    "zls",
}

return {
    {
        "folke/lazydev.nvim", -- Lua LSP for nvim config
        ft = "lua",
        opts = {
            library = {
                { path = "${3rd}/luv/library", words = { "vim%.uv" } },
            },
        },
    },
    { "rluba/jai.vim", ft = "jai" }, -- Jai language support
    { "lervag/vimtex", ft = { "tex", "plaintex" } }, -- LaTeX support
    {
        "saecki/crates.nvim", -- Cargo.toml crate info
        ft = "toml",
        config = function()
            require("crates").setup({})
        end
    },

    {
        "mason-org/mason.nvim", -- LSP/tool installer
        dependencies = {
            { "jay-babu/mason-null-ls.nvim" }, -- mason null-ls bridge
            { "neovim/nvim-lspconfig" }, -- LSP server configs
            { "nvimtools/none-ls.nvim" }, -- formatting/diagnostics via LSP
            { "mason-org/mason-lspconfig.nvim" }, -- mason lspconfig bridge
            { "WhoIsSethDaniel/mason-tool-installer.nvim" }, -- auto-install LSP tools
            { "marilari88/twoslash-queries.nvim" }, -- inline TS type hints
            {
                "ivanjermakov/troublesum.nvim", -- diagnostic count summary
                config = function()
                    require("troublesum").setup()
                end
            },
            {
                "MysticalDevil/inlay-hints.nvim", -- LSP inlay hints
                dependencies = { "neovim/nvim-lspconfig" },
                config = function()
                    require("inlay-hints").setup()
                end
            },
            {
                "Sebastian-Nielsen/better-type-hover", -- improved hover popup
                config = function()
                    require("better-type-hover").setup()
                end,
            },
            {
                "dmmulroy/ts-error-translator.nvim", -- readable TS errors
                config = function()
                    require("ts-error-translator").setup()
                end
            },
        },
        config = function()
            vim.diagnostic.config({
                severity_sort = true,
                update_in_insert = false,
                underline = true,
                virtual_text = {
                    prefix = "●",
                    spacing = 2,
                    source = "if_many",
                },
                float = {
                    border = "rounded",
                    source = "if_many",
                    header = "",
                },
                signs = {
                    text = {
                        [vim.diagnostic.severity.ERROR] = vim.fn.nr2char(0xea87), -- nf-cod-error
                        [vim.diagnostic.severity.WARN]  = vim.fn.nr2char(0xea6c), -- nf-cod-warning
                        [vim.diagnostic.severity.INFO]  = vim.fn.nr2char(0xea74), -- nf-cod-info
                        [vim.diagnostic.severity.HINT]  = vim.fn.nr2char(0xea61), -- nf-cod-lightbulb
                    },
                },
            })

            vim.api.nvim_create_autocmd("FileType", {
                pattern = "jai",
                callback = function(args)
                    vim.lsp.start({
                        name = "jails",
                        cmd = { "jails", "-jai_path", "/home/luca/.jai", "-jai_exe_name", "jai-linux" },
                        root_dir = vim.fs.root(args.buf, { "jails.json", ".git" }) or vim.fn.getcwd(),
                    })
                end,
            })

            require("mason").setup()
            require("mason-tool-installer").setup({
                ensure_installed = installed,
                -- upgrades run from scripts/system-update.sh, not on every startup
                run_on_start = false,
            })
            require("null-ls").setup()
            require("mason-null-ls").setup({
                ensure_installed = installed,
                handlers = {},
                automatic_installation = true,
            })

            vim.lsp.config("clangd", {
                cmd = {
                    "clangd",
                    "--offset-encoding=utf-16",
                    "--background-index",
                },
            })
            vim.lsp.enable("clangd")

            vim.lsp.config("rust_analyzer", {
                settings = {
                    ["rust-analyzer"] = {
                        cargo = {
                            allFeatures = true,
                            extraEnv = {
                                RUSTFLAGS = "--cfg kani_ra --cfg kani",
                                RUSTUP_TOOLCHAIN = "nightly",
                            },
                        },
                        check = {
                            command = "clippy",
                            extraEnv = {
                                RUSTFLAGS = "--cfg kani_ra --cfg kani",
                                RUSTUP_TOOLCHAIN = "nightly",
                            },
                        },
                    }
                }
            })
            vim.lsp.enable("rust_analyzer")

            vim.lsp.config("ts_ls", {
                on_attach = function(client, bufnr)
                    require("twoslash-queries").attach(client, bufnr)
                end,
            })
            vim.lsp.enable("ts_ls")

            require("mason-lspconfig").setup({
                automatic_enable = {
                    exclude = {
                        "clangd",
                        "rust_analyzer",
                        "ts_ls",
                    }
                }
            })
        end,
    },

    {
        "antosha417/nvim-lsp-file-operations", -- LSP-aware file ops
        dependencies = {
            "nvim-lua/plenary.nvim", -- Lua utility library
            "nvim-neo-tree/neo-tree.nvim", -- sidebar file tree
        },
        config = function()
            require("lsp-file-operations").setup()
        end,
    },

    {
        "stevearc/conform.nvim", -- code formatting
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
                    http = { "kulala-fmt" },
                    javascript = { "prettier" },
                    latex = { "latexindent" },
                    python = { "isort", "black" },
                    rest = { "kulala-fmt" },
                    rust = { "rustfmt", "sortderives", "leptosfmt" },
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
